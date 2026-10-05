import { Body, Controller, HttpCode, HttpStatus, Post } from '@nestjs/common';
import { ProfileView } from '../profile/profile.mapper';
import { AuthService } from './auth.service';
import { TokenResponse } from './auth.types';
import { CredentialsDto } from './dto/credentials.dto';

@Controller('auth')
export class AuthController {
  constructor(private readonly auth: AuthService) {}

  /** POST /auth/register -> 201 + new profile (starting money credited by the ledger trigger). */
  @Post('register')
  register(@Body() dto: CredentialsDto): Promise<ProfileView> {
    return this.auth.register(dto);
  }

  /** POST /auth/login -> 200 + RS256 access token. */
  @Post('login')
  @HttpCode(HttpStatus.OK)
  login(@Body() dto: CredentialsDto): Promise<TokenResponse> {
    return this.auth.login(dto);
  }
}
