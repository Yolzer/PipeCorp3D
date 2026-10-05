import { Controller, Get } from '@nestjs/common';
import { DatabaseService } from '../database/database.service';

@Controller('health')
export class HealthController {
  constructor(private readonly db: DatabaseService) {}

  /** GET /health -> confirms the API process AND the PostgreSQL pool are alive. */
  @Get()
  async check(): Promise<{ status: 'ok'; db: 'up' }> {
    await this.db.query<{ ok: number }>('SELECT 1 AS ok', []);
    return { status: 'ok', db: 'up' };
  }
}
