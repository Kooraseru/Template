async function exchange({ endpoint, audience, roles, requests, includeEvidence = false, environment, request = fetch }) {
	const broker = new URL(endpoint);
	const issuer = new URL(environment.ACTIONS_ID_TOKEN_REQUEST_URL);
	for (const url of [broker, issuer]) {
		if (url.protocol !== "https:" || url.username || url.password || url.hash) {
			throw new Error("OIDC requires HTTPS endpoints without embedded credentials");
		}
	}
	const requestToken = environment.ACTIONS_ID_TOKEN_REQUEST_TOKEN;
	if (!requestToken) throw new Error("GitHub OIDC authorization is unavailable");
	issuer.searchParams.set("audience", audience);
	const options = { redirect: "error", signal: AbortSignal.timeout(15_000) };
	const identity = await request(issuer, {
		...options,
		headers: { Authorization: `Bearer ${requestToken}` },
	});
	if (!identity.ok) throw new Error("GitHub rejected the OIDC token request");
	const { value } = await identity.json();
	if (typeof value !== "string" || !value) throw new Error("GitHub returned an invalid OIDC token");
	const response = await request(broker, {
		...options,
		method: "POST",
		headers: { Authorization: `Bearer ${value}`, "Content-Type": "application/json" },
		body: JSON.stringify({ profile: "source-ci", roles, requests }),
	});
	if (!response.ok) throw new Error("Credential broker rejected the exchange");
	const { credentials } = await response.json();
	if (!credentials || typeof credentials !== "object" || Array.isArray(credentials) || Object.keys(credentials).length === 0) {
		throw new Error("Credential broker returned an invalid response");
	}
	for (const [role, credential] of Object.entries(credentials)) {
		if (!roles.includes(role) || (typeof credential !== "string" && (!includeEvidence || typeof credential?.value !== "string")) || !(credential?.value ?? credential)) {
			throw new Error("Credential broker returned an invalid role or value");
		}
	}
	return credentials;
}

module.exports = { exchange };

if (require.main === module) {
	const [, , endpoint, audience, requested] = process.argv;
	Promise.resolve()
		.then(() => exchange({ endpoint, audience, roles: JSON.parse(requested), environment: process.env }))
		.then(credentials => process.stdout.write(JSON.stringify(credentials)))
		.catch(() => {
			process.stderr.write("OIDC credential exchange failed. Verify the broker, audience, and workflow trust policy.\n");
			process.exitCode = 1;
		});
}
