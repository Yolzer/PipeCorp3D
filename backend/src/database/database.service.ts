import { Injectable } from '@nestjs/common';
import { DataSource, QueryRunner } from 'typeorm';

/**
 * Whitelist of stored procedures the API may call. Function names cannot be
 * bound as SQL parameters, so restricting them to a literal union type removes
 * any identifier-injection surface at compile time.
 */
export type StoredProcedure =
  | 'sp_register_player'
  | 'sp_generate_ticket'
  | 'sp_expire_tickets'
  | 'sp_accept_ticket'
  | 'sp_complete_job'
  | 'sp_derive_ticket'
  | 'sp_report_public_tampering'
  | 'sp_apply_daily_upkeep'
  | 'sp_purchase_item'
  | 'sp_upgrade_vehicle';

@Injectable()
export class DatabaseService {
  constructor(private readonly dataSource: DataSource) {}

  /**
   * Runs `work` inside an explicit READ COMMITTED transaction on a dedicated
   * pooled connection (QueryRunner). Commit on success, rollback on any error,
   * and ALWAYS release the connection back to the pool.
   */
  async transaction<T>(work: (qr: QueryRunner) => Promise<T>): Promise<T> {
    const qr: QueryRunner = this.dataSource.createQueryRunner();
    await qr.connect();
    await qr.startTransaction('READ COMMITTED');
    try {
      const result: T = await work(qr);
      await qr.commitTransaction();
      return result;
    } catch (error: unknown) {
      await qr.rollbackTransaction();
      throw error;
    } finally {
      await qr.release();
    }
  }

  /** Calls a whitelisted stored procedure with positional bind parameters ($1..$n). */
  async callProcedure<T>(qr: QueryRunner, fn: StoredProcedure, params: readonly unknown[]): Promise<T[]> {
    const placeholders: string = params.map((_: unknown, i: number) => `$${i + 1}`).join(', ');
    const rows: T[] = await qr.query(`SELECT * FROM pipecorp.${fn}(${placeholders})`, [...params]);
    return rows;
  }

  /** Read-only parameterized query outside an explicit transaction. */
  async query<T>(sql: string, params: readonly unknown[]): Promise<T[]> {
    const rows: T[] = await this.dataSource.query(sql, [...params]);
    return rows;
  }
}
