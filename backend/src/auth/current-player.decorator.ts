import { createParamDecorator, ExecutionContext, UnauthorizedException } from '@nestjs/common';
import { AuthenticatedRequest, JwtPayload } from './auth.types';

/** Injects the verified JWT payload into a controller method: `@CurrentPlayer() p: JwtPayload`. */
export const CurrentPlayer = createParamDecorator((_data: unknown, ctx: ExecutionContext): JwtPayload => {
  const req: AuthenticatedRequest = ctx.switchToHttp().getRequest<AuthenticatedRequest>();
  if (req.player === undefined) {
    throw new UnauthorizedException('Route is missing JwtAuthGuard');
  }
  return req.player;
});
