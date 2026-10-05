import { ProfileRow, ProfileView, toProfileView } from './profile.mapper';

/** Anything that can run a parameterized query: DataSource or a QueryRunner inside a transaction. */
export interface Queryable {
  query(sql: string, params?: unknown[]): Promise<unknown>;
}

export async function loadProfile(db: Queryable, playerId: string, username: string): Promise<ProfileView | null> {
  const rows = (await db.query(
    `SELECT pp.*, vt.name AS vehicle_name, vt.inventory_capacity
       FROM pipecorp.plumber_profiles pp
       JOIN pipecorp.vehicle_tiers vt ON vt.id = pp.vehicle_tier_id
      WHERE pp.player_id = $1`,
    [playerId],
  )) as ProfileRow[];
  const row: ProfileRow | undefined = rows[0];
  return row === undefined ? null : toProfileView(row, username);
}
