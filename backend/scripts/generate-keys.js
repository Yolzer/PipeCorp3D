// Generates the RS256 key pair used to sign (private) and verify (public) JWTs.
// Run once: `npm run keys`. Output goes to keys/*.pem (git-ignored).
const { generateKeyPairSync } = require('node:crypto');
const { writeFileSync, existsSync, mkdirSync } = require('node:fs');
const { join } = require('node:path');

const dir = join(__dirname, '..', 'keys');
if (!existsSync(dir)) mkdirSync(dir);

const priv = join(dir, 'private.pem');
if (existsSync(priv) && !process.argv.includes('--force')) {
  console.log('keys/private.pem already exists. Use `npm run keys -- --force` to rotate.');
  process.exit(0);
}

const { publicKey, privateKey } = generateKeyPairSync('rsa', {
  modulusLength: 2048,
  publicKeyEncoding: { type: 'spki', format: 'pem' },
  privateKeyEncoding: { type: 'pkcs8', format: 'pem' },
});

writeFileSync(priv, privateKey, { mode: 0o600 });
writeFileSync(join(dir, 'public.pem'), publicKey);
console.log('RS256 key pair written to keys/private.pem and keys/public.pem');
