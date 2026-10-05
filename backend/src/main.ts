import 'reflect-metadata';
import { Logger } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import { NestFactory } from '@nestjs/core';
import { AppModule } from './app.module';
import { configureApp } from './app.setup';

async function bootstrap(): Promise<void> {
  const app = await NestFactory.create(AppModule);
  configureApp(app);
  const port: number = app.get(ConfigService).getOrThrow<number>('PORT');
  await app.listen(port);
  Logger.log(`PipeCorp3D API listening on http://localhost:${port}`, 'Bootstrap');
}

void bootstrap();
