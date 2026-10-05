import { CanActivate, ExecutionContext, Injectable, UnauthorizedException } from '@nestjs/common';
import { JwtService } from '@nestjs/jwt';
import { AuthenticatedRequest, JwtPayload } from './auth.types';

/**
 * Verifies `Authorization: Bearer <jwt>` with the RSA PUBLIC key only.
 * The algorithm whitelist (RS256) is enforced in JwtModule.verifyOptions, which
 * blocks the classic "alg confusion" attack (HS256 signed with the public key).
 */
@Injectable()
export class JwtAuthGuard implements CanActivate {
  constructor(private readonly jwt: JwtService) {}

  async canActivate(context: ExecutionContext): Promise<boolean> {
    const req: AuthenticatedRequest = context.switchToHttp().getRequest<AuthenticatedRequest>();
    const header: string | undefined = req.headers.authorization;
    if (header === undefined || !header.startsWith('Bearer ')) {
      throw new UnauthorizedException('Missing bearer token');
    }
    try {
      req.player = await this.jwt.verifyAsync<JwtPayload>(header.slice('Bearer '.length));
      return true;
    } catch {
      throw new UnauthorizedException('Invalid or expired token');
    }
  }
}
