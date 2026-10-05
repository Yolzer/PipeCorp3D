import { validateEnv } from './env.validation';

const BASE: Record<string, unknown> = {
  DB_HOST: 'localhost',
  DB_USER: 'postgres',
  DB_PASSWORD: 'x',
  DB_NAME: 'pipecorp3d',
  JWT_PRIVATE_KEY_PATH: 'keys/private.pem',
  JWT_PUBLIC_KEY_PATH: 'keys/public.pem',
};

describe('validateEnv', () => {
  it('applies typed defaults', () => {
    const env = validateEnv(BASE);
    expect(env.PORT).toBe(3000);
    expect(env.DB_POOL_MAX).toBe(10);
    expect(env.JWT_TTL_SECONDS).toBe(7200);
  });

  it('fails fast on a missing required variable', () => {
    const { DB_PASSWORD: _omit, ...rest } = BASE;
    expect(() => validateEnv(rest)).toThrow(/DB_PASSWORD/);
  });

  it('rejects an out-of-range pool size', () => {
    expect(() => validateEnv({ ...BASE, DB_POOL_MAX: '500' })).toThrow(/DB_POOL_MAX/);
  });
});
