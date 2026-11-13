"use strict";

const fs = require("node:fs");
const path = require("node:path");
const { spawnSync } = require("node:child_process");

const ROOT = path.resolve(__dirname, "../..");
const CONFIG = path.join(ROOT, ".github/config/ci/settings.toml");
const { parse: parseToml } = require(path.join(ROOT, "dependencies/packages/core/dependencyLoader/vendor/toml.cjs"));
const EVENTS = new Set(["push", "pull_request", "workflow_dispatch"]);
const NAME = /^[a-z][a-z0-9-]*$/;
const ALIAS = /^[A-Z][A-Z0-9_]*$/;
const PREFIX = /^[a-z][a-z0-9/-]*-$/;
const COMPONENT = /^[a-z0-9][a-z0-9_-]*(?:\/[a-z0-9][a-z0-9_-]*)*$/;

function object(value, label) {
	if (!value || typeof value !== "object" || Array.isArray(value)) throw new Error(label + " must be an object");
	return value;
}

function readConfig(filename = CONFIG, { requireCredentials = true } = {}) {
	const config = object(parseToml(fs.readFileSync(filename, "utf8")), "CI settings");
	if (config.version !== 1) throw new Error("Unsupported CI operations format");
	const checks = object(config.checks, "checks");
	const operations = object(config.operations, "operations");
	const triggers = object(config.triggers, "triggers");
	const bootstrap = object(config.bootstrap, "bootstrap");
	if (!NAME.test(bootstrap.environment) || Object.keys(bootstrap).some(key => key !== "environment")) {
		throw new Error("Invalid bootstrap environment");
	}
	if (requireCredentials) {
		const catalog = require(path.join(ROOT, "ci/github/authentication/catalog.cjs"))
			.load(path.join(ROOT, ".github/config/credentials.json"));
		const sourceProfile = catalog.profiles["source-ci"];
		const binding = catalog.environments[bootstrap.environment];
		if (sourceProfile.bootstrapEnvironment !== bootstrap.environment || !binding) {
			throw new Error("CI bootstrap environment must match the credential catalog's source-ci profile");
		}
		function alias(role, namespace) {
			const value = binding[role], prefix = namespace + ".";
			if (typeof value !== "string" || !value.startsWith(prefix) || !ALIAS.test(value.slice(prefix.length))) {
				throw new Error("Invalid bootstrap credential alias for " + role);
			}
			return value.slice(prefix.length);
		}
		bootstrap.appIdVariable = alias("app_id", "vars");
		bootstrap.appPrivateKeySecret = alias("app_private_key", "secrets");
		bootstrap.bootstrapTokenSecret = alias("bootstrap_token", "secrets");
	}
	for (const [name, item] of Object.entries(checks)) {
		if (!NAME.test(name)) throw new Error("Invalid check identity: " + name);
		object(item, "check " + name);
		if (item.group !== undefined && !["review", "audit"].includes(item.group)) throw new Error("Invalid check group: " + name);
		if (!Array.isArray(item.command) || !item.command.length ||
			item.command.some(arg => typeof arg !== "string" || !arg || /[\r\n\0]/.test(arg))) {
			throw new Error("Invalid check command: " + name);
		}
		if (!Number.isSafeInteger(item.timeoutSeconds) || item.timeoutSeconds < 1 || item.timeoutSeconds > 3600) {
			throw new Error("Invalid check timeout: " + name);
		}
	}
	for (const [name, item] of Object.entries(operations)) {
		if (!NAME.test(name)) throw new Error("Invalid operation identity: " + name);
		object(item, "operation " + name);
		if (!["generated", "readonly"].includes(item.mode)) throw new Error("Invalid operation mode: " + name);
		if (!Array.isArray(item.events) || !item.events.length || item.events.some(event => !EVENTS.has(event))) {
			throw new Error("Invalid operation events: " + name);
		}
		if (item.mode === "readonly") {
			if (!Array.isArray(item.checks) || !item.checks.length || item.checks.some(check => !Object.hasOwn(checks, check))) {
				throw new Error("Unknown checks for operation: " + name);
			}
			if (item.events.includes("push")) throw new Error("Push operations must execute through generated branches");
		} else if (typeof item.plan !== "string" || !NAME.test(item.plan) || typeof item.publication !== "boolean" ||
			typeof item.branchPrefix !== "string" || !PREFIX.test(item.branchPrefix) ||
			item.branchPrefix.includes("//") || item.branchPrefix.includes("..")) {
			throw new Error("Invalid generated operation: " + name);
		}
		if (item.components !== undefined && (!Array.isArray(item.components) || !item.components.length ||
			item.components.some(name => typeof name !== "string" || !COMPONENT.test(name)) ||
			new Set(item.components).size !== item.components.length)) {
			throw new Error("Invalid component selection: " + name);
		}
		if (item.publication && !item.events.every(event => event === "push" || event === "workflow_dispatch")) {
			throw new Error("Publication cannot be configured for untrusted events: " + name);
		}
	}
	for (const [event, name] of Object.entries(triggers)) {
		if (!EVENTS.has(event) || !Object.hasOwn(operations, name) || !operations[name].events.includes(event)) {
			throw new Error("Invalid event route: " + event);
		}
	}
	for (const event of EVENTS) if (!Object.hasOwn(triggers, event)) throw new Error("Missing event route: " + event);
	return config;
}

function resolve(config, env = process.env) {
	const event = env.GITHUB_EVENT_NAME || "workflow_dispatch";
	if (!EVENTS.has(event)) throw new Error("Unsupported GitHub event: " + event);
	const requested = event === "workflow_dispatch" ? env.CI_REQUESTED_OPERATION || config.triggers[event] : config.triggers[event];
	if (!NAME.test(requested) || !Object.hasOwn(config.operations, requested)) throw new Error("Unknown CI operation: " + requested);
	const operation = config.operations[requested];
	if (!operation.events.includes(event)) throw new Error("Operation " + requested + " is unavailable for " + event);
	if (operation.mode === "generated") {
		if (event === "pull_request") throw new Error("Untrusted pull requests cannot launch a generated privileged workflow");
		if (env.ACT !== "true" && env.GITHUB_REF !== "refs/heads/source") throw new Error("Generated CI requires the trusted source ref");
		if (event === "workflow_dispatch" && operation.publication && env.CI_REQUESTED_PUBLISH !== "true") {
			throw new Error("Manual publication requires explicit publish=true");
		}
	}
	const groups = operation.mode === "readonly" ? operation.checks.map(name => config.checks[name].group || "review") : [];
	return { event, name: requested, ...operation, bootstrap: config.bootstrap,
		reviewChecks: groups.includes("review"), auditChecks: groups.includes("audit") };
}

function appendOutputs(route, file) {
	if (!file) return;
	const output = {
		operation: route.name,
		mode: route.mode,
		environment: route.bootstrap.environment,
		app_id_name: route.bootstrap.appIdVariable,
		app_private_key_name: route.bootstrap.appPrivateKeySecret,
		bootstrap_token_name: route.bootstrap.bootstrapTokenSecret,
		plan: route.plan || "validation",
		publication: route.publication ? "true" : "false",
		branch_prefix: route.branchPrefix || "",
		review_checks: route.reviewChecks ? "true" : "false",
		audit_checks: route.auditChecks ? "true" : "false",
	};
	for (const [name, value] of Object.entries(output)) {
		if (String(value).includes("\n") || String(value).includes("\r")) throw new Error("Unsafe CI output");
		fs.appendFileSync(file, name + "=" + value + "\n");
	}
}

function runReadonly(config, route, workspace = ROOT, env = process.env) {
	if (route.mode !== "readonly") throw new Error("Only unprivileged operations may run inside the launcher");
	const group = env.CI_CHECK_GROUP || "review";
	if (!["review", "audit"].includes(group)) throw new Error("Invalid read-only check group");
	const selected = route.checks.filter(name => (config.checks[name].group || "review") === group);
	if (!selected.length) throw new Error("No checks configured for group " + group);
	const childEnv = { ...env, CI_EVENT: "pull_request", CI_OPERATION: "validation" };
	for (const key of Object.keys(childEnv)) {
		if (key === "GH_TOKEN" || key === "GITHUB_TOKEN" || key.startsWith("CI_CREDENTIAL_") ||
			key.startsWith("ACTIONS_ID_TOKEN_REQUEST_") || key === "CI_SECRETS") delete childEnv[key];
	}
	for (const name of selected) {
		const check = config.checks[name];
		console.log("::group::CI check: " + name);
		const result = spawnSync(check.command[0], check.command.slice(1), {
			cwd: workspace, env: childEnv, stdio: "inherit", timeout: check.timeoutSeconds * 1000, shell: false,
		});
		console.log("::endgroup::");
		if (result.error || result.status !== 0) throw new Error(name + " failed: " +
			(result.error?.message || "exit " + result.status));
	}
}

function main(args = process.argv.slice(2), env = process.env) {
	const action = args[0] || "resolve";
	if (!["resolve", "run", "verify"].includes(action)) throw new Error("Unknown CI router command");
	// The read-only runner must reach its configured dependency setup without importing managed packages.
	const config = readConfig(CONFIG, { requireCredentials: action !== "run" });
	if (action === "verify") return;
	const route = resolve(config, env);
	if (action === "resolve") {
		appendOutputs(route, env.GITHUB_OUTPUT);
		console.log("::notice::Selected " + route.name + " (" + route.mode + ")");
		return;
	}
	runReadonly(config, route, ROOT, env);
}

module.exports = { readConfig, resolve, appendOutputs, runReadonly, main };
if (require.main === module) {
	try { main(); } catch (error) {
		console.error("::error::" + (error instanceof Error ? error.message : String(error)));
		process.exitCode = 1;
	}
}
