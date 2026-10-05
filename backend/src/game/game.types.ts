import { ProfileView } from '../profile/profile.mapper';

/** Raw row from pipecorp.tickets (BIGINT/NUMERIC arrive as strings from node-postgres). */
export interface TicketRow {
  id: string;
  zone: 'PRIVATE' | 'PUBLIC';
  description: string;
  difficulty: number;
  estimated_parts: number;
  target_seconds: number;
  required_xp: number;
  budget: string;
  status: string;
  expires_at: Date;
}

export interface TicketView {
  id: number;
  zone: 'PRIVATE' | 'PUBLIC';
  description: string;
  difficulty: number;
  estimatedParts: number;
  targetSeconds: number;
  requiredXp: number;
  budget: number;
  status: string;
  expiresAt: string;
  expiresAtUnix: number;
}

export interface JobRow {
  ticket_id: string;
  grade: string;
  payout: string;
  xp_gained: number;
}

export interface JobResultView {
  ticketId: number;
  grade: string;
  payout: number;
  xpGained: number;
}

export interface InventoryView {
  itemCode: string;
  quantity: number;
}

export interface ProfileEnvelope {
  profile: ProfileView;
}

export function toTicketView(row: TicketRow): TicketView {
  const expires: Date = new Date(row.expires_at);
  return {
    id: Number(row.id),
    zone: row.zone,
    description: row.description,
    difficulty: row.difficulty,
    estimatedParts: row.estimated_parts,
    targetSeconds: row.target_seconds,
    requiredXp: row.required_xp,
    budget: Number(row.budget),
    status: row.status,
    expiresAt: expires.toISOString(),
    expiresAtUnix: Math.floor(expires.getTime() / 1000),
  };
}
