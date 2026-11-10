const test = require("node:test");
const assert = require("node:assert/strict");
const fs = require("node:fs");
const os = require("node:os");
const path = require("node:path");
const { load } = require("./catalog.cjs");
const { select } = require("./selector.cjs");

const repo = "example/project";
const requests = ["bootstrap_token", "projects_token", "rulesets_token"].map(role => ({
	role, service: "github", operation: role, target: repo,
}));

function automaticCatalog() {
	const catalog = load();
	catalog.sources.actions = { provider: "github-context", discovery: "automatic" };
	return catalog;
}

test("discovers a renamed PAT, ranks narrow grants, and caches duplicate probes", async () => {
	const probes = new Map();
	const result = await select({
		catalog: automaticCatalog(), profile: "source-ci", requests,
		secrets: {
			Renamed: "ghp_shared", Alias: "ghp_shared", Narrow: "ghp_narrow",
			Denied: "ghp_denied", Expired: "ghp_expired", Fine: "github_pat_dummy",
			Unrelated: "other-service-key", GITHUB_TOKEN: "ghp_builtin",
		},
		environment: {},
		fetcher: async (url, options) => {
			assert.equal(options.redirect, "error");
			const credential = options.headers.Authorization.split(" ")[1];
			assert.ok(["ghp_shared", "ghp_narrow", "ghp_denied", "ghp_expired"].includes(credential));
			const key = credential + url;
			probes.set(key, (probes.get(key) ?? 0) + 1);
			if (credential === "ghp_expired") return new Response(null, { status: 401 });
			if (url.endsWith("/user")) {
				return new Response(null, { headers: {
					"x-oauth-scopes": credential === "ghp_shared" ? "repo, workflow, project" : "repo",
				} });
			}
			return new Response(null, { status: credential === "ghp_denied" ? 403 : 200 });
		},
	});
	assert.equal(result.credentials.bootstrap_token, "ghp_shared");
	assert.equal(result.credentials.projects_token, "ghp_shared");
	assert.equal(result.credentials.rulesets_token, "ghp_narrow");
	assert.equal(result.evidence.rulesets_token.targetAccess, "observed");
	assert.ok([...probes.values()].every(count => count === 1));
});

test("leaves unverified fine-grained credentials unselected", async () => {
	const result = await select({
		catalog: automaticCatalog(), profile: "source-ci", requests,
		secrets: { Unverified: "github_pat_dummy" }, environment: {},
		fetcher: () => assert.fail("No probe should be sent"),
	});
	assert.deepEqual(Object.keys(result.credentials), []);
	assert.equal(result.evidence.bootstrap_token.counts.unverified, 1);
});

test("requires OIDC grant evidence for the requested operation and targets", async () => {
	const catalog = load();
	catalog.sources.broker = { provider: "oidc" };
	catalog.profiles["source-ci"].sources = ["broker"];
	const result = await select({
		catalog, profile: "source-ci", requests, environment: {},
		broker: async input => {
			assert.deepEqual({ ...input.requests[0].requirements.repository }, { contents: "write", workflows: "write" });
			return {
				bootstrap_token: {
					value: "github_pat_dummy",
					grants: { target: repo, operation: "bootstrap_token", repository: { contents: "write", workflows: "write" } },
				},
				rulesets_token: {
					value: "github_pat_wrong_target",
					grants: { target: "wrong/project", operation: "rulesets_token", repository: { administration: "write" } },
				},
			};
		},
	});
	assert.equal(result.credentials.bootstrap_token, "github_pat_dummy");
	assert.equal(result.credentials.rulesets_token, undefined);
});

test("uses command source and verifier with a service-specific request", async () => {
	const catalog = load();
	catalog.sources.zones = { provider: "command", command: ["inventory"] };
	catalog.verifiers.zones = { provider: "command", command: ["verify"] };
	catalog.roles.zone_token = {
		selection: "capability", verifier: "zones", candidateSources: ["zones"],
		service: "cloudflare", target: "zone-1", requirements: { dns: "write" },
	};
	catalog.profiles["source-ci"].sources = ["actions", "zones"];
	const result = await select({
		catalog, profile: "source-ci", requests: [{ role: "zone_token", operation: "dns/update" }],
		secrets: { Unrelated: "ghp_unrelated" }, environment: {},
		command: async ([name], input) => {
			if (name === "inventory") return [{ value: "dummy-external", metadata: { region: "example" } }];
			assert.equal(input.request.service, "cloudflare");
			assert.equal(input.request.target, "zone-1");
			assert.deepEqual(input.request.requirements, { dns: "write" });
			assert.equal(input.candidate.metadata.region, "example");
			return { state: "verified", kind: "provider grant" };
		},
	});
	assert.equal(result.credentials.zone_token, "dummy-external");
});

test("validates comments, reference integrity, and duplicate keys", () => {
	const directory = fs.mkdtempSync(path.join(os.tmpdir(), "template-credentials-"));
	try {
		const file = path.join(directory, "credentials.json");
		const original = fs.readFileSync(".github/config/credentials.json", "utf8");
		fs.writeFileSync(file, original);
		assert.ok(load(file).roles.bootstrap_token);
		fs.writeFileSync(file, original.replace('"actions"\n      ]', '"missing"\n      ]'));
		assert.throws(() => load(file), /Unknown source/);
		fs.writeFileSync(file, original.replace('"neutralCheck":', '"roles": {}, "neutralCheck":'));
		assert.throws(() => load(file), /Duplicate/);
	} finally {
		fs.rmSync(directory, { recursive: true, force: true });
	}
});
