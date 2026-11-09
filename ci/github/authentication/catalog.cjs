const fs = require("node:fs");
const path = require("node:path");
const modules = path.resolve(__dirname, "../../../build/dependencies/npm/node_modules");
const { parseTree, getNodeValue, visit } = require(path.join(modules, "jsonc-parser"));
const Ajv = require(path.join(modules, "ajv"));
const schema = require("../../../.github/config/credentials.schema.json");

const empty = { classic: [], repository: {}, organization: {} };

function load(file = ".github/config/credentials.json") {
	const input = fs.readFileSync(file, "utf8");
	const errors = [];
	const tree = parseTree(input, errors);
	if (!tree || errors.length) throw new Error("Invalid credential catalog JSONC");
	const keys = [];
	visit(input, {
		onObjectBegin: () => keys.push(new Set()),
		onObjectEnd: () => keys.pop(),
		onObjectProperty: key => {
			if (keys.at(-1).has(key)) throw new Error("Duplicate credential catalog property");
			keys.at(-1).add(key);
		},
	});
	const catalog = getNodeValue(tree);
	// Migrate the previous named-only shape in memory.
	if (!catalog.sources && !catalog.verifiers && catalog.roles && catalog.profiles?.["source-ci"]) {
		const profile = catalog.profiles["source-ci"];
		catalog.sources = { hosted: profile.credentialProvider === "oidc"
			? { provider: "oidc", ...profile.oidc }
			: { provider: "github-context", discovery: "listed", secrets: [] } };
		catalog.verifiers = {};
		for (const role of Object.values(catalog.roles)) role.selection = "named";
		for (const [id, entry] of Object.entries(catalog.profiles)) {
			delete entry.credentialProvider;
			delete entry.oidc;
			entry.sources = id === "source-ci" ? ["hosted"] : [];
		}
	}
	const validate = new Ajv({ strict: false }).compile(schema);
	if (!validate(catalog)) throw new Error("Invalid credential catalog " + validate.errors.map(error => error.instancePath + " " + error.message).join(", "));
	for (const source of Object.values(catalog.sources)) {
		if (source.discovery === "listed" && !source.secrets?.length && catalog.verifiers.github) {
			throw new Error("Listed discovery requires explicit secret keys");
		}
		if (source.provider === "oidc") {
			const endpoint = new URL(source.endpoint);
			if (endpoint.protocol !== "https:" || endpoint.username || endpoint.password || endpoint.hash) {
				throw new Error("Invalid OIDC credential endpoint");
			}
		}
	}
	for (const [id, role] of Object.entries(catalog.roles)) {
		if (role.verifier && !Object.hasOwn(catalog.verifiers, role.verifier)) throw new Error("Unknown verifier for role " + id);
		if (role.candidateSources?.some(source => !Object.hasOwn(catalog.sources, source))) throw new Error("Unknown candidate source for role " + id);
		if (role.verifier && catalog.verifiers[role.verifier].provider === "command" && !role.candidateSources?.length) {
			throw new Error("Custom verifier requires candidateSources for role " + id);
		}
		role.permissions = { ...empty, ...(role.requirements ?? role.permissions) };
		if (catalog.verifiers[role.verifier]?.provider === "github" &&
			(!Array.isArray(role.permissions.classic) || role.permissions.classic.some(scope => typeof scope !== "string" || !/^[\w:]+$/.test(scope)))) {
			throw new Error("Invalid classic scopes for role " + id);
		}
		role.sources ??= ["secret"];
		// Keep compatibility with existing role-based reports and named consumers.
		role.name ??= role.fallbackName ?? id;
	}
	for (const [name, profile] of Object.entries(catalog.profiles)) {
		const sources = profile.sources.map(id => {
			if (!Object.hasOwn(catalog.sources, id)) throw new Error("Unknown source in profile " + name);
			return catalog.sources[id];
		});
		for (const role of profile.bootstrap) {
			if (!Object.hasOwn(catalog.roles, role)) throw new Error("Unknown bootstrap role in profile " + name);
		}
		const transports = sources.filter(source => source.provider !== "command");
		if (transports.length > 1) throw new Error("Choose one hosted credential transport per profile");
		const [transport] = transports;
		profile.githubContext = transport?.provider === "github-context";
		profile.contextKeys = profile.githubContext ? (transport.secrets ?? []) : [];
		profile.usesCommands = sources.some(source => source.provider === "command");
		if (name === "source-ci") profile.credentialProvider = transport?.provider ?? "github-context";
		if (transport?.provider === "oidc") profile.oidc = { endpoint: transport.endpoint, audience: transport.audience };
	}
	return catalog;
}

module.exports = { load };
if (require.main === module) {
	try { process.stdout.write(JSON.stringify(load(process.argv[2]))); }
	catch (error) { process.stderr.write(error.message + "\n"); process.exitCode = 1; }
}
