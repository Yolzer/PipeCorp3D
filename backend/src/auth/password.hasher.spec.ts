import { PasswordHasher } from './password.hasher';

describe('PasswordHasher (scrypt)', () => {
  const hasher: PasswordHasher = new PasswordHasher();

  it('hashes in the scrypt$N$r$p$salt$hash format and never stores plaintext', async () => {
    const stored: string = await hasher.hash('Sup3rSecreta!');
    expect(stored.startsWith('scrypt$16384$8$1$')).toBe(true);
    expect(stored).not.toContain('Sup3rSecreta!');
  });

  it('verifies the correct password', async () => {
    const stored: string = await hasher.hash('Sup3rSecreta!');
    await expect(hasher.verify('Sup3rSecreta!', stored)).resolves.toBe(true);
  });

  it('rejects a wrong password', async () => {
    const stored: string = await hasher.hash('Sup3rSecreta!');
    await expect(hasher.verify('sup3rsecreta!', stored)).resolves.toBe(false);
  });

  it('uses a random salt (same password -> different hashes)', async () => {
    const a: string = await hasher.hash('same-password');
    const b: string = await hasher.hash('same-password');
    expect(a).not.toEqual(b);
  });

  it('rejects malformed stored hashes instead of throwing', async () => {
    await expect(hasher.verify('x', 'not-a-hash')).resolves.toBe(false);
  });
});
