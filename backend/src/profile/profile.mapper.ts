/**
 * node-postgres returns NUMERIC as string (to avoid float precision loss) and
 * BIGINT as string. The game client needs plain numbers, so we map explicitly.
 */
export interface ProfileRow {
  player_id: string;
  entity_id: string;
  money: string; //            NUMERIC(12,2)
  xp: number;
  reputation: number;
  vehicle_tier_id: number;
  game_day: number;
  is_game_over: boolean;
  game_over_reason: 'BANKRUPTCY' | 'SISS_TAMPERING' | null;
  vehicle_name?: string;
  inventory_capacity?: number;
}

export interface ProfileView {
  playerId: string;
  username: string;
  entityId: string;
  money: number;
  xp: number;
  reputation: number;
  vehicleTierId: number;
  vehicleName: string | null;
  inventoryCapacity: number | null;
  gameDay: number;
  isGameOver: boolean;
  gameOverReason: 'BANKRUPTCY' | 'SISS_TAMPERING' | null;
}

export function toProfileView(row: ProfileRow, username: string): ProfileView {
  return {
    playerId: row.player_id,
    username,
    entityId: row.entity_id,
    money: Number(row.money),
    xp: row.xp,
    reputation: row.reputation,
    vehicleTierId: row.vehicle_tier_id,
    vehicleName: row.vehicle_name ?? null,
    inventoryCapacity: row.inventory_capacity ?? null,
    gameDay: row.game_day,
    isGameOver: row.is_game_over,
    gameOverReason: row.game_over_reason,
  };
}
