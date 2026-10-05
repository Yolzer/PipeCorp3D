import { Injectable, NotFoundException } from '@nestjs/common';
import { QueryRunner } from 'typeorm';
import { JwtPayload } from '../auth/auth.types';
import { DatabaseService } from '../database/database.service';
import { ProfileView } from '../profile/profile.mapper';
import { loadProfile } from '../profile/profile.repository';
import {
  InventoryView, JobResultView, JobRow, ProfileEnvelope, TicketRow, TicketView, toTicketView,
} from './game.types';

/** Material the MVP uses for every job (matches Godot PlumberEntity.selected_item). */
export const DEFAULT_JOB_ITEM: string = 'pvc_90_deg';
/** Spare parts bought on accept so the player can waste up to this many and still finish. */
export const SPARE_PARTS: number = 2;
/** The ticket board always keeps at least this many OPEN tickets. */
export const BOARD_SIZE: number = 3;

interface TicketTemplate {
  zone: 'PRIVATE' | 'PUBLIC';
  description: string;
  difficulty: number;
  estimatedParts: number;
}

/** Deterministic ticket pool (cycled by the player's ticket count, so tests are reproducible). */
const TEMPLATES: readonly TicketTemplate[] = [
  { zone: 'PRIVATE', description: 'Fuga bajo el lavaplatos', difficulty: 1, estimatedParts: 2 },
  { zone: 'PRIVATE', description: 'Cambio de sifón en baño', difficulty: 2, estimatedParts: 3 },
  { zone: 'PUBLIC', description: 'Fuga en el medidor de la vereda', difficulty: 2, estimatedParts: 2 },
  { zone: 'PRIVATE', description: 'Instalación de lavadero', difficulty: 3, estimatedParts: 4 },
  { zone: 'PRIVATE', description: 'Filtración en la conexión del calefont', difficulty: 2, estimatedParts: 3 },
  { zone: 'PUBLIC', description: 'Arranque público dañado frente a la casa', difficulty: 3, estimatedParts: 3 },
];
const TICKET_TTL_SECONDS: number = 300;

const TICKET_COLUMNS: string =
  'id, zone, description, difficulty, estimated_parts, target_seconds, required_xp, budget, status, expires_at';

@Injectable()
export class GameService {
  constructor(private readonly db: DatabaseService) {}

  private async profile(qr: QueryRunner, player: JwtPayload): Promise<ProfileView> {
    const profile: ProfileView | null = await loadProfile(qr, player.sub, player.username);
    if (profile === null) throw new NotFoundException('Profile not found');
    return profile;
  }

  /** GET /tickets: expire stale tickets, top the board up to BOARD_SIZE, return OPEN + ACCEPTED. */
  listTickets(player: JwtPayload): Promise<{ tickets: TicketView[] }> {
    return this.db.transaction(async (qr: QueryRunner) => {
      await this.db.callProcedure(qr, 'sp_expire_tickets', [player.sub]);
      const counts = (await qr.query(
        `SELECT COUNT(*) FILTER (WHERE status = 'OPEN')::int AS open_count,
                COUNT(*)::int AS total
           FROM pipecorp.tickets WHERE player_id = $1`,
        [player.sub],
      )) as { open_count: number; total: number }[];
      const openCount: number = counts[0]?.open_count ?? 0;
      let cursor: number = counts[0]?.total ?? 0;

      for (let i: number = openCount; i < BOARD_SIZE; i++, cursor++) {
        const tpl: TicketTemplate = TEMPLATES[cursor % TEMPLATES.length] as TicketTemplate;
        await this.db.callProcedure(qr, 'sp_generate_ticket', [
          player.sub, tpl.zone, tpl.description, tpl.difficulty, tpl.estimatedParts,
          45 + 30 * tpl.difficulty, TICKET_TTL_SECONDS, 0,
        ]);
      }

      // SISS triage must always be available: keep at least one OPEN public ticket on the board.
      const publics = (await qr.query(
        `SELECT COUNT(*)::int AS n FROM pipecorp.tickets WHERE player_id = $1 AND status = 'OPEN' AND zone = 'PUBLIC'`,
        [player.sub],
      )) as { n: number }[];
      if ((publics[0]?.n ?? 0) === 0) {
        const pool: TicketTemplate[] = TEMPLATES.filter((t: TicketTemplate) => t.zone === 'PUBLIC');
        const tpl: TicketTemplate = pool[cursor % pool.length] as TicketTemplate;
        await this.db.callProcedure(qr, 'sp_generate_ticket', [
          player.sub, tpl.zone, tpl.description, tpl.difficulty, tpl.estimatedParts,
          45 + 30 * tpl.difficulty, TICKET_TTL_SECONDS, 0,
        ]);
      }

      const rows = (await qr.query(
        `SELECT ${TICKET_COLUMNS} FROM pipecorp.tickets
          WHERE player_id = $1 AND status IN ('OPEN', 'ACCEPTED') ORDER BY id`,
        [player.sub],
      )) as TicketRow[];
      return { tickets: rows.map(toTicketView) };
    });
  }

  /**
   * POST /tickets/:id/accept — accepts the ticket AND buys the missing materials in ONE
   * transaction (no store UI in the MVP). If funds/capacity fail, the accept rolls back too.
   */
  acceptTicket(player: JwtPayload, ticketId: number): Promise<{ ticket: TicketView } & ProfileEnvelope> {
    return this.db.transaction(async (qr: QueryRunner) => {
      const accepted = await this.db.callProcedure<TicketRow>(qr, 'sp_accept_ticket', [player.sub, ticketId]);
      const ticket: TicketRow = accepted[0] as TicketRow;

      const stock = (await qr.query(
        `SELECT COALESCE(SUM(i.quantity), 0)::int AS qty
           FROM pipecorp.inventory i JOIN pipecorp.items it ON it.id = i.item_id
          WHERE i.player_id = $1 AND it.code = $2`,
        [player.sub, DEFAULT_JOB_ITEM],
      )) as { qty: number }[];
      const missing: number = ticket.estimated_parts + SPARE_PARTS - (stock[0]?.qty ?? 0);
      if (missing > 0) {
        await this.db.callProcedure(qr, 'sp_purchase_item', [player.sub, DEFAULT_JOB_ITEM, missing]);
      }
      return { ticket: toTicketView(ticket), profile: await this.profile(qr, player) };
    });
  }

  completeJob(
    player: JwtPayload, ticketId: number, itemCode: string, timeSeconds: number, partsUsed: number, partsWasted: number,
  ): Promise<{ result: JobResultView } & ProfileEnvelope> {
    return this.db.transaction(async (qr: QueryRunner) => {
      const jobs = await this.db.callProcedure<JobRow>(qr, 'sp_complete_job', [
        player.sub, ticketId, itemCode, timeSeconds, partsUsed, partsWasted,
      ]);
      const job: JobRow = jobs[0] as JobRow;
      return {
        result: { ticketId: Number(job.ticket_id), grade: job.grade, payout: Number(job.payout), xpGained: job.xp_gained },
        profile: await this.profile(qr, player),
      };
    });
  }

  deriveTicket(player: JwtPayload, ticketId: number): Promise<ProfileEnvelope> {
    return this.profileAfter(player, 'sp_derive_ticket', [player.sub, ticketId]);
  }

  reportTampering(player: JwtPayload, ticketId: number): Promise<ProfileEnvelope> {
    return this.profileAfter(player, 'sp_report_public_tampering', [player.sub, ticketId]);
  }

  endDay(player: JwtPayload): Promise<ProfileEnvelope> {
    return this.profileAfter(player, 'sp_apply_daily_upkeep', [player.sub]);
  }

  upgradeVehicle(player: JwtPayload, tierId: number): Promise<ProfileEnvelope> {
    return this.profileAfter(player, 'sp_upgrade_vehicle', [player.sub, tierId]);
  }

  purchase(player: JwtPayload, itemCode: string, quantity: number): Promise<{ inventory: InventoryView } & ProfileEnvelope> {
    return this.db.transaction(async (qr: QueryRunner) => {
      const rows = await this.db.callProcedure<{ quantity: number }>(qr, 'sp_purchase_item', [player.sub, itemCode, quantity]);
      return {
        inventory: { itemCode, quantity: rows[0]?.quantity ?? 0 },
        profile: await this.profile(qr, player),
      };
    });
  }

  async inventory(player: JwtPayload): Promise<{ items: InventoryView[] }> {
    const rows = await this.db.query<{ item_code: string; quantity: number }>(
      `SELECT it.code AS item_code, i.quantity
         FROM pipecorp.inventory i JOIN pipecorp.items it ON it.id = i.item_id
        WHERE i.player_id = $1 AND i.quantity > 0 ORDER BY it.id`,
      [player.sub],
    );
    return { items: rows.map((r) => ({ itemCode: r.item_code, quantity: r.quantity })) };
  }

  /** Runs one stored procedure and returns the refreshed authoritative profile, atomically. */
  private profileAfter(
    player: JwtPayload,
    fn: 'sp_derive_ticket' | 'sp_report_public_tampering' | 'sp_apply_daily_upkeep' | 'sp_upgrade_vehicle',
    params: readonly unknown[],
  ): Promise<ProfileEnvelope> {
    return this.db.transaction(async (qr: QueryRunner) => {
      await this.db.callProcedure(qr, fn, params);
      return { profile: await this.profile(qr, player) };
    });
  }
}
