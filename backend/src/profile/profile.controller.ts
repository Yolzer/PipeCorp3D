import { Controller, Get, NotFoundException, UseGuards } from '@nestjs/common';
import { DataSource } from 'typeorm';
import { CurrentPlayer } from '../auth/current-player.decorator';
import { JwtPayload } from '../auth/auth.types';
import { JwtAuthGuard } from '../auth/jwt-auth.guard';
import { ProfileView } from './profile.mapper';
import { loadProfile } from './profile.repository';

@Controller('profile')
@UseGuards(JwtAuthGuard)
export class ProfileController {
  constructor(private readonly dataSource: DataSource) {}

  /** GET /profile -> authoritative game state for the logged-in player (Godot "Login/Load"). */
  @Get()
  async me(@CurrentPlayer() player: JwtPayload): Promise<ProfileView> {
    const profile: ProfileView | null = await loadProfile(this.dataSource, player.sub, player.username);
    if (profile === null) throw new NotFoundException('Profile not found');
    return profile;
  }
}
