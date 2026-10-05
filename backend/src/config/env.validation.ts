// Fail-fast environment validation: the API refuses to boot with bad config.
export interface AppEnv {
  PORT: number;
  DB_HOST: string;
  DB_PORT: number;
  DB_USER: string;
  DB_PASSWORD: string;
  DB_NAME: string;
  DB_POOL_MAX: number;
  JWT_PRIVATE_KEY_PATH: string;
  JWT_PUBLIC_KEY_PATH: string;
  JWT_TTL_SECONDS: number;
}

const REQUIRED_STRINGS = [
  'DB_HOST',
  'DB_USER',
  'DB_PASSWORD',
  'DB_NAME',
  'JWT_PRIVATE_KEY_PATH',
  'JWT_PUBLIC_KEY_PATH',
] as const;

function toInt(raw: unknown, name: string, fallback: number, min: number, max: number): number {
  const value: number = raw === undefined || raw === '' ? fallback : Number(raw);
  if (!Number.isInteger(value) || value < min || value > max) {
    throw new Error(`Invalid env ${name}: must be an integer in [${min}, ${max}]`);
  }
  return value;
}

export function validateEnv(raw: Record<string, unknown>): AppEnv {
  for (const key of REQUIRED_STRINGS) {
    const v: unknown = raw[key];
    if (typeof v !== 'string' || v.trim() === '') {
      throw new Error(`Missing required env ${key} (see .env.example)`);
    }
  }
  return {
    PORT: toInt(raw.PORT, 'PORT', 3000, 1, 65535),
    DB_HOST: String(raw.DB_HOST),
    DB_PORT: toInt(raw.DB_PORT, 'DB_PORT', 5432, 1, 65535),
    DB_USER: String(raw.DB_USER),
    DB_PASSWORD: String(raw.DB_PASSWORD),
    DB_NAME: String(raw.DB_NAME),
    DB_POOL_MAX: toInt(raw.DB_POOL_MAX, 'DB_POOL_MAX', 10, 1, 50),
    JWT_PRIVATE_KEY_PATH: String(raw.JWT_PRIVATE_KEY_PATH),
    JWT_PUBLIC_KEY_PATH: String(raw.JWT_PUBLIC_KEY_PATH),
    JWT_TTL_SECONDS: toInt(raw.JWT_TTL_SECONDS, 'JWT_TTL_SECONDS', 7200, 60, 86400),
  };
}
