import type { Request } from 'express';

/** Claims carried by the RS256 access token. */
export interface JwtPayload {
  sub: string; //      players.id (UUID)
  username: string;
  entity: string; //   Godot PlumberEntity.player_id, e.g. "Player_1"
}

export interface AuthenticatedRequest extends Request {
  player?: JwtPayload;
}

export interface TokenResponse {
  access_token: string;
  token_type: 'Bearer';
  expires_in: number;
}
