const { sign } = require('node:crypto');
const { readFileSync } = require('node:fs');

const [issuer, keyPath] = process.argv.slice(2);
const now = Math.floor(Date.now() / 1000);
const encode = value => Buffer.from(JSON.stringify(value)).toString('base64url');
const header = encode({ alg: 'RS256', typ: 'JWT' });
const claims = encode({ iat: now - 60, exp: now + 540, iss: issuer });
const message = `${header}.${claims}`;

const signature = sign('RSA-SHA256', Buffer.from(message), readFileSync(keyPath));
process.stdout.write(`${message}.${signature.toString('base64url')}`);
