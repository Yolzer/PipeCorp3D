import { Injectable } from '@nestjs/common';
import { randomBytes, scrypt, ScryptOptions, timingSafeEqual } from 'node:crypto';

/**
 * Password hashing with Node's built-in scrypt (memory-hard KDF).
 * Zero native dependencies -> installs cleanly on Windows (no node-gyp).
 * Stored format: scrypt$N$r$p$<salt b64>$<hash b64>
 */
const KEY_LENGTH: number = 64;
const PARAMS: Readonly<Required<Pick<ScryptOptions, 'N' | 'r' | 'p'>>> = { N: 16384, r: 8, p: 1 };

function deriveKey(password: string, salt: Buffer, keyLength: number, options: ScryptOptions): Promise<Buffer> {
  return new Promise<Buffer>((resolve, reject) => {
    scrypt(password, salt, keyLength, options, (err: Error | null, key: Buffer) => {
      if (err) reject(err);
      else resolve(key);
    });
  });
}

@Injectable()
export class PasswordHasher {
  async hash(password: string): Promise<string> {
    const salt: Buffer = randomBytes(16);
    const key: Buffer = await deriveKey(password, salt, KEY_LENGTH, PARAMS);
    return ['scrypt', PARAMS.N, PARAMS.r, PARAMS.p, salt.toString('base64'), key.toString('base64')].join('$');
  }

  async verify(password: string, stored: string): Promise<boolean> {
    const parts: string[] = stored.split('$');
    if (parts.length !== 6 || parts[0] !== 'scrypt') return false;
    const [, n, r, p, saltB64, hashB64] = parts as [string, string, string, string, string, string];
    const expected: Buffer = Buffer.from(hashB64, 'base64');
    const actual: Buffer = await deriveKey(password, Buffer.from(saltB64, 'base64'), expected.length, {
      N: Number(n),
      r: Number(r),
      p: Number(p),
    });
    // Constant-time comparison prevents timing attacks on the hash bytes.
    return actual.length === expected.length && timingSafeEqual(actual, expected);
  }
}
