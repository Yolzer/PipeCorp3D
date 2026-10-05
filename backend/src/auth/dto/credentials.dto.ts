import { IsString, Matches, MaxLength, MinLength } from 'class-validator';

/** Same username rule as the CHECK constraint on pipecorp.players.username. */
export class CredentialsDto {
  @IsString()
  @Matches(/^[A-Za-z0-9_]{3,32}$/, { message: 'username: 3-32 chars, letters, digits or _' })
  username!: string;

  @IsString()
  @MinLength(8)
  @MaxLength(72)
  password!: string;
}
