import { Injectable, UnauthorizedException } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import { JwtService } from '@nestjs/jwt';
import { QueryRunner } from 'typeorm';
import { DatabaseService } from '../database/database.service';
import { ProfileRow, ProfileView, toProfileView } from '../profile/profile.mapper';
import { JwtPayload, TokenResponse } from './auth.types';
import { CredentialsDto } from './dto/credentials.dto';
import { PasswordHasher } from './password.hasher';

interface PlayerAuthRow {
  id: string;
  username: string;
  password_hash: string;
  entity_id: string;
}

@Injectable()
export class AuthService {
  /** Pre-computed hash used when the username does not exist, so both paths cost the same (anti user-enumeration). */
  private dummyHash: Promise<string>;

  constructor(
    private readonly db: DatabaseService,
    private readonly hasher: PasswordHasher,
    private readonly jwt: JwtService,
    private readonly config: ConfigService,
  ) {
    this.dummyHash = this.hasher.hash('timing-equalizer-password');
  }

  async register(dto: CredentialsDto): Promise<ProfileView> {
    const passwordHash: string = await this.hasher.hash(dto.password);
    const rows: ProfileRow[] = await this.db.transaction((qr: QueryRunner) =>
      this.db.callProcedure<ProfileRow>(qr, 'sp_register_player', [dto.username, passwordHash]),
    );
    const row: ProfileRow | undefined = rows[0];
    if (row === undefined) throw new Error('sp_register_player returned no row');
    return toProfileView(row, dto.username);
  }

  async login(dto: CredentialsDto): Promise<TokenResponse> {
    const rows: PlayerAuthRow[] = await this.db.query<PlayerAuthRow>(
      `SELECT p.id, p.username, p.password_hash, pp.entity_id
         FROM pipecorp.players p
         JOIN pipecorp.plumber_profiles pp ON pp.player_id = p.id
        WHERE p.username = $1`,
      [dto.username],
    );
    const player: PlayerAuthRow | undefined = rows[0];
    const valid: boolean = await this.hasher.verify(dto.password, player?.password_hash ?? (await this.dummyHash));
    if (player === undefined || !valid) {
      throw new UnauthorizedException('Invalid credentials'); // same message for both cases
    }

    const payload: JwtPayload = { sub: player.id, username: player.username, entity: player.entity_id };
    return {
      access_token: await this.jwt.signAsync(payload),
      token_type: 'Bearer',
      expires_in: this.config.getOrThrow<number>('JWT_TTL_SECONDS'),
    };
  }
}
