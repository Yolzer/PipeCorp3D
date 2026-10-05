import { ArgumentsHost, Catch, ExceptionFilter, HttpStatus, Logger } from '@nestjs/common';
import type { Response } from 'express';
import { QueryFailedError } from 'typeorm';

/** Custom SQLSTATEs raised by 02_triggers.sql / 03_procedures.sql -> HTTP. */
export const SQLSTATE_TO_HTTP: Readonly<Record<string, HttpStatus>> = {
  PC001: HttpStatus.CONFLICT, //               Game Over
  PC002: HttpStatus.NOT_FOUND, //              entity not found
  PC003: HttpStatus.CONFLICT, //               invalid state / FSM
  PC004: HttpStatus.UNPROCESSABLE_ENTITY, //   insufficient funds
  PC005: HttpStatus.UNPROCESSABLE_ENTITY, //   inventory capacity
  PC006: HttpStatus.FORBIDDEN, //              insufficient XP
  PC007: HttpStatus.INTERNAL_SERVER_ERROR, //  immutable record touched
  '23505': HttpStatus.CONFLICT, //             unique_violation (e.g. username taken)
  '23514': HttpStatus.BAD_REQUEST, //          check_violation
  '22P02': HttpStatus.BAD_REQUEST, //          invalid_text_representation (bad uuid)
};

interface PgDriverError {
  code?: string;
  message?: string;
}

@Catch(QueryFailedError)
export class PgErrorFilter implements ExceptionFilter {
  private readonly logger: Logger = new Logger(PgErrorFilter.name);

  catch(exception: QueryFailedError, host: ArgumentsHost): void {
    const res: Response = host.switchToHttp().getResponse<Response>();
    const driver: PgDriverError = exception.driverError as PgDriverError;
    const code: string = driver.code ?? 'UNKNOWN';
    const status: HttpStatus = SQLSTATE_TO_HTTP[code] ?? HttpStatus.INTERNAL_SERVER_ERROR;

    // Business errors (PCxxx) carry safe, intentional messages. Anything else is
    // logged server-side and returned generically to avoid leaking schema details.
    const isBusiness: boolean = code.startsWith('PC');
    const message: string = isBusiness
      ? driver.message ?? 'Business rule violation'
      : code === '23505'
        ? 'Resource already exists'
        : 'Database error';

    if (!isBusiness) {
      this.logger.warn(`SQLSTATE ${code}: ${driver.message ?? exception.message}`);
    }
    res.status(status).json({ statusCode: status, code, message });
  }
}
