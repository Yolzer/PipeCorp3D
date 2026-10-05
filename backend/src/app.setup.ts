import { INestApplication, ValidationPipe } from '@nestjs/common';
import { PgErrorFilter } from './database/pg-error.filter';

/** Shared bootstrap so production (main.ts) and e2e tests run the exact same pipeline. */
export function configureApp(app: INestApplication): void {
  app.useGlobalPipes(
    new ValidationPipe({
      whitelist: true, //            strip unknown fields
      forbidNonWhitelisted: true, // ...or reject them with 400
      transform: true,
    }),
  );
  app.useGlobalFilters(new PgErrorFilter());
  app.enableShutdownHooks(); //    releases the pg pool on SIGTERM / Ctrl+C
}
