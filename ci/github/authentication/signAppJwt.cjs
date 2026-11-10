const { sign } = require('node:crypto');
const { readFileSync } = require('node:fs');

const [issuer, keyPath, repository, permissionJson, organization] = process.argv.slice(2);

function makeJwt() {
	const now = Math.floor(Date.now() / 1000);
	const encode = value => Buffer.from(JSON.stringify(value)).toString('base64url');
	const header = encode({ alg: 'RS256', typ: 'JWT' });
	const claims = encode({ iat: now - 60, exp: now + 540, iss: issuer.trim() });
	const message = `${header}.${claims}`;
	const signature = sign('RSA-SHA256', Buffer.from(message), readFileSync(keyPath));
	return `${message}.${signature.toString('base64url')}`;
}

async function exchange() {
	const jwt = makeJwt();
	const api = process.env.GITHUB_API_URL || 'https://api.github.com';
	const request = (path, options) => fetch(`${api}${path}`, {
		...options,
		redirect: 'error',
		signal: AbortSignal.timeout(30_000),
		headers: {
			Authorization: `Bearer ${jwt}`,
			Accept: 'application/vnd.github+json',
			'Content-Type': 'application/json',
			'User-Agent': 'Template-CI-bootstrap',
		},
	});
	const path = organization ? `/orgs/${organization}/installation` : `/repos/${repository}/installation`;
	const installation = await request(path);
	if (!installation.ok) {
		const body = await installation.json().catch(() => ({}));
		const known = {
			'A JSON web token could not be decoded': 'GitHub could not decode the App JWT',
			'Invalid issuer (iss) claim': 'GitHub rejected the App JWT issuer',
			'JWT signature could not be verified': 'GitHub could not verify the App JWT signature',
		};
		return fail((installation.status === 401 && Object.hasOwn(known, body?.message))
			? known[body.message] : `GitHub App installation lookup returned HTTP ${installation.status}`);
	}
	const { id } = await installation.json();
	if (!Number.isSafeInteger(id)) return fail('GitHub returned an invalid App installation ID');
	const created = await request(`/app/installations/${id}/access_tokens`, {
		method: 'POST',
		body: JSON.stringify({
			repositories: organization ? undefined : [repository.split('/').at(-1)],
			permissions: JSON.parse(permissionJson) ?? undefined,
		}),
	});
	if (!created.ok) return fail(`App installation token request returned HTTP ${created.status}`);
	const { token } = await created.json();
	process.stdout.write(JSON.stringify({ token }));
}

function fail(message) {
	process.stdout.write(message);
	process.exitCode = 1;
}

exchange().catch(() => fail('GitHub App exchange failed'));
