const { createHash } = require("node:crypto");
const fingerprint = value => createHash("sha256").update(value).digest("hex");
const { spawnSync } = require("node:child_process");
const { load } = require("./catalog.cjs");
const { exchange } = require("./oidc.cjs");

const classicPat = /^ghp_[A-Za-z0-9]+$/;
const fineGrainedPat = /^github_pat_[A-Za-z0-9_]+$/;
const states = new Set(["verified", "insufficient", "invalid", "unverified"]);

function runCommand(command, request) {
	// Adapters receive their request through stdin and have no ambient CI credentials.
	const env = Object.fromEntries(Object.entries(process.env).filter(([key]) =>
		/^(PATH|PATHEXT|SYSTEMROOT|WINDIR|TEMP|TMP|TMPDIR)$/i.test(key)));
	const result = spawnSync(command[0], command.slice(1), {
		input: JSON.stringify(request), env, encoding: "utf8", timeout: 15_000, maxBuffer: 1024 * 1024,
	});
	if (result.status !== 0) throw new Error("Credential adapter failed");
	return JSON.parse(result.stdout);
}

function githubOrigin(environment) {
	const api = new URL(environment.GITHUB_API_URL || "https://api.github.com");
	const server = new URL(environment.GITHUB_SERVER_URL || "https://github.com");
	const cloud = server.hostname === "github.com" || server.hostname.endsWith(".ghe.com");
	const expectedHost = cloud ? "api." + server.hostname : server.hostname;
	if (api.protocol !== "https:" || server.protocol !== "https:" || api.hostname !== expectedHost
		|| api.port !== server.port || api.username || api.password || api.search || api.hash
		|| api.pathname.replace(/\/$/, "") !== (cloud ? "" : "/api/v3")) {
		throw new Error("Untrusted GitHub API endpoint");
	}
	return api.href.replace(/\/$/, "");
}

function covers(granted, scope) {
	const [level, resource] = scope.split(":");
	return granted.includes(scope) || (resource && granted.includes(level))
		|| (level === "read" && resource && granted.includes("write:" + resource))
		|| (["read", "write"].includes(level) && resource && granted.includes("admin:" + resource))
		|| (scope === "public_repo" && granted.includes("repo"));
}

async function select({ catalog, profile, requests, secrets = {}, variables = {}, environment = process.env,
	fetcher = fetch, command = runCommand, broker = exchange }) {
	const chosen = Object.create(null);
	const evidence = Object.create(null);
	const scopesCache = new Map();
	const targetCache = new Map();
	const requestCache = new Map();
	const scopedRequests = requests.map(request => {
		if (!Object.hasOwn(catalog.roles, request.role)) throw new Error("Unknown credential role");
		const role = catalog.roles[request.role];
		return { ...request, service: role.service ?? role.verifier ?? request.service, target: role.target ?? request.target, targets: role.target ? [role.target] : (request.targets ?? [request.target]), operation: role.operation ?? request.operation, verifier: role.verifier, requirements: role.requirements ?? role.permissions };
	});
	const profileConfig = catalog.profiles[profile];
	if (!profileConfig) throw new Error("Unknown credential profile");

	const lookup = (map, name) => Object.entries(map).find(([key]) => key.toUpperCase() === name.toUpperCase())?.[1];
	const validValue = value => typeof value === "string" && value.length > 0 && value !== environment.GH_TOKEN;
	const cached = (cache, key, read) => {
		if (!cache.has(key)) cache.set(key, read());
		return cache.get(key);
	};
	async function githubRequest(value, route) {
		try {
			return await fetcher(githubOrigin(environment) + route, {
				headers: { Authorization: "Bearer " + value, Accept: "application/vnd.github+json" },
				redirect: "error", signal: AbortSignal.timeout(8_000),
			});
		} catch { return null; }
	}
	async function verify(candidate, request, sourceId) {
		const role = catalog.roles[request.role];
		const verifier = catalog.verifiers[role.verifier];
		if (verifier.provider === "command") {
			if (!role.candidateSources?.includes(sourceId)) return { state: "unverified" };
			const result = await command(verifier.command, { request, candidate });
			if (!states.has(result?.state) || (result.extraPermissions !== undefined
				&& (!Number.isSafeInteger(result.extraPermissions) || result.extraPermissions < 0))) {
				throw new Error("Credential verifier returned invalid evidence");
			}
			return result;
		}
		if (candidate.grants) {
			const grants = candidate.grants;
			const coveredTargets = Array.isArray(grants.targets) ? grants.targets : [grants.target];
			const matches = request.targets.every(target => coveredTargets.includes(target)) && grants.operation === request.operation;
			const contains = group => Object.entries(request.requirements[group] ?? {}).every(([key, access]) =>
				grants[group]?.[key] === access || (access === "read" && grants[group]?.[key] === "write"));
			const fineGrainedRequirements = Object.keys(request.requirements.repository ?? {}).length
				+ Object.keys(request.requirements.organization ?? {}).length;
			const classic = Array.isArray(grants.classic) && (request.requirements.classic ?? []).every(scope => covers(grants.classic, scope));
			if (matches && (fineGrainedRequirements ? contains("repository") && contains("organization") : classic)) {
				return { state: "verified", kind: "broker grants" };
			}
		}
		if (!classicPat.test(candidate.value)) return { state: "unverified" };
		const response = await cached(scopesCache, candidate.value, () => githubRequest(candidate.value, "/user"));
		if (response?.status === 401) return { state: "invalid" };
		const scopes = response?.ok ? response.headers.get("x-oauth-scopes") : null;
		if (scopes === null) return { state: "unverified" };
		const granted = scopes.split(",").map(scope => scope.trim()).filter(Boolean);
		const required = request.requirements.classic ?? [];
		const missing = required.filter(scope => !covers(granted, scope));
		if (missing.length) return { state: "insufficient", missing };
		let targetAccess = "unverified";
		if (/^[\w.-]+\/[\w.-]+$/.test(request.target) && Object.keys(request.requirements.repository ?? {}).length) {
			const route = "/repos/" + request.target.split("/").map(encodeURIComponent).join("/");
			const checked = await cached(targetCache, candidate.value + "\n" + route, () => githubRequest(candidate.value, route));
			if (checked && [401, 403, 404].includes(checked.status)) return { state: "insufficient", targetAccess: "denied" };
			if (checked?.ok) targetAccess = "observed";
		}
		return { state: "verified", kind: "classic scopes", targetAccess, extraPermissions: granted.filter(scope => !required.includes(scope)).length };
	}
	for (const sourceId of profileConfig.sources) {
		const source = catalog.sources[sourceId];
		const pending = scopedRequests.filter(request => !Object.hasOwn(chosen, request.role));
		if (!pending.length) break;
		let supplied;
		if (source.provider === "oidc") {
			supplied = await broker({ ...source, environment, roles: pending.map(request => request.role), requests: pending, includeEvidence: true });
		} else if (source.provider === "command") {
			supplied = await command(source.command, { profile, requests: pending });
			if (!Array.isArray(supplied) || supplied.some(candidate => !candidate || !validValue(candidate.value))) {
				throw new Error("Credential source returned invalid candidates");
			}
		}
		for (const request of pending) {
			const role = catalog.roles[request.role];
			if (role.candidateSources && !role.candidateSources.includes(sourceId)) continue;
			let candidates = [];
			if (source.provider === "github-context") {
				if (role.selection === "named") {
					for (const kind of role.sources) {
						const value = lookup(kind === "secret" ? secrets : variables, role.name);
						if (validValue(value)) { candidates.push({ value }); break; }
					}
				} else if (catalog.verifiers[role.verifier].provider === "github") {
					const eligible = source.discovery === "listed" ? (source.secrets ?? []).filter(key => key.toUpperCase() !== "GITHUB_TOKEN").map(key => lookup(secrets, key)) : Object.entries(secrets).filter(([key]) => key.toUpperCase() !== "GITHUB_TOKEN").map(([, value]) => value);
					candidates = [...new Set(eligible)].filter(value => validValue(value) && (classicPat.test(value) || fineGrainedPat.test(value)))
						.sort((a, b) => fingerprint(a).localeCompare(fingerprint(b))).map(value => ({ value }));
				} else if (source.discovery === "listed") {
					candidates = (source.secrets ?? []).filter(key => key.toUpperCase() !== "GITHUB_TOKEN")
						.map(key => lookup(secrets, key)).filter(validValue).map(value => ({ value }));
				}
			} else if (source.provider === "oidc") {
				const item = supplied[request.role];
				if (validValue(item?.value ?? item)) candidates = [typeof item === "string" ? { value: item } : item];
			} else {
				candidates = supplied.filter(candidate => candidate.role === request.role || (role.selection === "capability" && !candidate.role));
			}
			if (role.selection === "named") {
				if (candidates.length) chosen[request.role] = candidates[0].value;
				continue;
			}
			let best;
			const counts = { invalid: 0, insufficient: 0, unverified: 0 };
			for (const candidate of candidates) {
				const key = JSON.stringify([sourceId, request, candidate]);
				const result = await cached(requestCache, key, () => verify(candidate, request, sourceId));
				if (result.state !== "verified") { counts[result.state]++; continue; }
				if (!best || (result.extraPermissions ?? Infinity) < (best.result.extraPermissions ?? Infinity)) best = { candidate, result };
			}
			if (best) {
				chosen[request.role] = best.candidate.value;
				evidence[request.role] = { state: "verified", kind: best.result.kind ?? "provider evidence", targetAccess: best.result.targetAccess };
			} else {
				evidence[request.role] = { state: "unverified", counts };
			}
		}
	}
	for (const request of scopedRequests) {
		const role = catalog.roles[request.role];
		if (Object.hasOwn(chosen, request.role) || !role.fallbackName
			|| !profileConfig.sources.some(id => catalog.sources[id].provider === "github-context")) continue;
		const value = lookup(secrets, role.fallbackName);
		if (!validValue(value)) continue;
		const result = await verify({ value }, request, "");
		if (result.state === "verified") {
			chosen[request.role] = value;
			evidence[request.role] = { state: "verified", kind: result.kind, targetAccess: result.targetAccess };
		}
	}
	return { credentials: chosen, evidence };
}

module.exports = { select };
if (require.main === module) {
	Promise.resolve().then(() => select({ catalog: load(), ...JSON.parse(process.env.CI_SELECTOR_REQUEST) }))
		.then(result => process.stdout.write(JSON.stringify(result)))
		.catch(() => {
			process.stderr.write("Credential selection failed. Check the catalog, source, and verifier configuration.\n");
			process.exitCode = 1;
		});
}
