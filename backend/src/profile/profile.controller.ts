import { Controller, Get, NotFoundException, UseGuards } from '@nestjs/common';
import { CurrentPlayer } from '../auth/current-player.decorator';
import { JwtPayload } from '../auth/auth.types';
import { JwtAuthGuard } from '../auth/jwt-auth.guard';
import { DatabaseService } from '../database/database.service';
import { ProfileRow, ProfileView, toProfileView } from './profile.mapper';

@Controller('profile')
@UseGuards(JwtAuthGuard)
export class ProfileController {
  constructor(private readonly db: DatabaseService) {}

  /** GET /profile -> authoritative game state for the logged-in player (Godot "Login/Load"). */
  @Get()
  async me(@CurrentPlayer() player: JwtPayload): Promise<ProfileView> {
    const rows: ProfileRow[] = await this.db.query<ProfileRow>(
      `SELECT pp.*, vt.name AS vehicle_name, vt.inventory_capacity
         FROM pipecorp.plumber_profiles pp
         JOIN pipecorp.vehicle_tiers vt ON vt.id = pp.vehicle_tier_id
        WHERE pp.player_id = $1`,
      [player.sub],
    );
    const row: ProfileRow | undefined = rows[0];
    if (row === undefined) throw new NotFoundException('Profile not found');
    return toProfileView(row, player.username);
  }
}
