import { Module } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import { JwtModule, JwtModuleOptions } from '@nestjs/jwt';
import { readFileSync } from 'node:fs';
import { resolve } from 'node:path';
import { AuthController } from './auth.controller';
import { AuthService } from './auth.service';
import { JwtAuthGuard } from './jwt-auth.guard';
import { PasswordHasher } from './password.hasher';

const ISSUER: string = 'pipecorp3d-api';

@Module({
  imports: [
    JwtModule.registerAsync({
      global: true,
      inject: [ConfigService],
      useFactory: (config: ConfigService): JwtModuleOptions => ({
        // Asymmetric: only this API holds the private key (signs);
        // any service (or future game server) can verify with the public key.
        privateKey: readFileSync(resolve(config.getOrThrow<string>('JWT_PRIVATE_KEY_PATH')), 'utf8'),
        publicKey: readFileSync(resolve(config.getOrThrow<string>('JWT_PUBLIC_KEY_PATH')), 'utf8'),
        signOptions: {
          algorithm: 'RS256',
          expiresIn: config.getOrThrow<number>('JWT_TTL_SECONDS'),
          issuer: ISSUER,
        },
        verifyOptions: {
          algorithms: ['RS256'], // whitelist: rejects HS256/none tokens
          issuer: ISSUER,
        },
      }),
    }),
  ],
  controllers: [AuthController],
  providers: [AuthService, PasswordHasher, JwtAuthGuard],
  exports: [JwtAuthGuard],
})
export class AuthModule {}
