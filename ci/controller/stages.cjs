"use strict";

// An eight-stage CI controller. Each entry point consumes only verified upstream artifacts.
const fs = require("node:fs");
const path = require("node:path");
const os = require("node:os");
const { spawnSync, spawn } = require("node:child_process");
const C = require("./contracts.cjs");
const { ROOT, STATE, assert, sha256, write, read, output, graph } = C;
const TOOLCHAIN = path.join(STATE, "toolchain");
const GENERATED = path.join(STATE, "generated");
const LOGS = path.join(STATE, "logs");
process.chdir(ROOT);

const fileHash = filename => sha256(fs.readFileSync(filename));
const mkdir = filename => fs.mkdirSync(path.dirname(filename), { recursive: true });
const fail = message => { throw new Error(message); };
function command(program, args, options = {}) {
	const result = spawnSync(program, args, { cwd: ROOT, encoding: "utf8", maxBuffer: 8 * 1024 * 1024, ...options });
	if (result.error || result.status !== 0) throw new Error(program + " failed: " + (result.stderr || result.error?.message || "exit " + result.status).slice(0, 1500));
	return result.stdout.trim();
}
function context() {
	return C.trust(process.env.GITHUB_EVENT_NAME || "workflow_dispatch",
		process.env.GITHUB_REF || "refs/heads/source",
		process.env.GITHUB_REPOSITORY || "Kooraseru/Template",
		process.env.GITHUB_SHA || command("git", ["rev-parse", "HEAD"]));
}
function requireSource(expected) {
	const current = context();
	assert(current.sha === expected.sha && current.repository === expected.repository &&
		current.event === expected.event && current.level === expected.level, "Controller source provenance mismatch");
}
function save(kind, value) {
	const result = write(kind, value);
	output({ digest: result.digest });
	return result;
}
function eventForPlan(operation) {
	return operation.mode === "generated" ? "push" : operation.event;
}
function loadOperation() {
	const manifest = read("operation", process.env.CI_OPERATION_DIGEST);
	requireSource(manifest.trust);
	return manifest;
}
function stageToolchain() {
	const trust = context();
	const bundle = path.join(TOOLCHAIN, "managed.tar.gz");
	const metadata = path.join(TOOLCHAIN, "bundle.json");
	fs.mkdirSync(TOOLCHAIN, { recursive: true });
	assert(fs.existsSync("dependencies/managed"), "Common managed dependencies were not installed");
	command("tar", ["--dereference", "-czf", bundle, "dependencies/managed"]);
	const snapshot = { version: 1, source: trust.sha, run: process.env.GITHUB_RUN_ID || "local",
		trust: trust.level, archive: "managed.tar.gz", digest: fileHash(bundle) };
	fs.writeFileSync(metadata, JSON.stringify(snapshot, null, 2) + "\n");
	output({ digest: snapshot.digest });
	console.log("Prepared common dependency bundle " + snapshot.digest);
}
function restore() {
	const bundle = path.join(TOOLCHAIN, "managed.tar.gz");
	const metadata = JSON.parse(fs.readFileSync(path.join(TOOLCHAIN, "bundle.json"), "utf8"));
	const expected = process.env.CI_TOOLCHAIN_DIGEST;
	assert(metadata.version === 1 && /^[a-f0-9]{64}$/.test(metadata.digest), "Invalid toolchain metadata");
	assert(!expected || expected === metadata.digest, "Unexpected toolchain identity");
	assert(metadata.digest === fileHash(bundle), "Toolchain archive integrity failure");
	assert(metadata.source === context().sha && metadata.trust === context().level &&
		metadata.run === (process.env.GITHUB_RUN_ID || "local"), "Toolchain trust or run mismatch");
	const listing = command("tar", ["-tzf", bundle]).split("\n").filter(Boolean);
	assert(listing.length > 0 && listing.every(entry => (entry === "dependencies/managed/" ||
		entry.startsWith("dependencies/managed/")) && !entry.split("/").includes("..")), "Toolchain archive escapes managed dependencies");
	const types = command("tar", ["-tvzf", bundle]).split("\n").filter(Boolean);
	const members = new Set(listing.map(entry => entry.replace(/\/$/, "")));
	for (const line of types) {
		const type = line[0];
		if (type === "d" || type === "-") continue;
		if (type === "h") {
			const target = line.match(/ link to ([^\r\n]+)$/)?.[1];
			assert(target && target.startsWith("dependencies/managed/") && !target.split("/").includes("..") &&
				members.has(target), "Toolchain hardlink points outside its verified archive");
			continue;
		}
		throw new Error("Toolchain archive contains a link or special file type: " + type);
	}
	command("tar", ["-xzf", bundle, "-C", ROOT]);
	console.log("Restored verified dependency bundle");
}
function resolveOperation() {
	const { readConfig, resolve } = require("../bootstrap/routes.cjs");
	const cfg = readConfig();
	const operation = resolve(cfg);
	const trust = context();
	if (operation.mode === "generated") assert(trust.level === "trusted-source", "Generated execution requires trusted source");
	if (trust.level === "untrusted") assert(operation.mode === "readonly", "Untrusted operation must be read-only");
	const checks = operation.mode === "readonly" ? operation.checks.map(id => {
		const entry = cfg.checks[id];
		return { id, kind: "command", boundary: "read", needs: entry.needs || (id === "setup" || !operation.checks.includes("setup") ? [] : ["setup"]),
			command: entry.command, timeoutSeconds: entry.timeoutSeconds };
	}) : [];
	if (checks.length) graph(checks);
	const componentFiles = command("git", ["ls-files", "ci/components"]).split("\n")
		.filter(name => name.endsWith("/component.toml"));
	const manifest = save("operation", {
		trust, name: operation.name, mode: operation.mode, event: operation.event,
		plan: operation.plan || "validation", publication: operation.publication === true,
		branchPrefix: operation.branchPrefix || "", checks,
		components: operation.components || null,
		componentContracts: componentFiles.map(filename => ({ filename, sha256: fileHash(filename) })),
	});
	output({ operation: manifest.name, mode: manifest.mode });
}
function checkPermissions() {
	const operation = loadOperation();
	const catalog = require("../github/authentication/catalog.cjs").load();
	const safe = operation.mode === "readonly";
	const profile = catalog.profiles[operation.mode === "generated" ? "source-ci" : "validate"];
	assert(profile, "Missing authorization profile");
	const environment = safe ? "ci-untrusted" : profile.bootstrapEnvironment;
	const reporting = safe ? environment : profile.reportingEnvironment;
	const bindings = safe ? {} : catalog.environments[environment];
	const reportBindings = safe ? {} : catalog.environments[reporting];
	assert(safe || (bindings?.app_id && bindings?.app_private_key && bindings?.bootstrap_token), "No bootstrap binding");
	assert(safe || (reportBindings?.app_id && reportBindings?.app_private_key), "No reporting binding");
	const alias = (record, role, prefix) => {
		const value = record?.[role] || "";
		assert(!value || new RegExp("^" + prefix + "\\.[A-Z][A-Z0-9_]*$").test(value), "Invalid source binding");
		return value ? value.slice(prefix.length + 1) : "";
	};
	const capabilities = safe ? [] : profile.bootstrap.map(role => ({
		role, requirements: catalog.roles[role].requirements || catalog.roles[role].permissions,
		source: catalog.sources[profile.sources[0]]?.provider || "unknown",
		state: "planned", // Never assert that a runtime secret exists here.
	}));
	if (safe) assert(capabilities.length === 0, "Untrusted execution requested privileged capabilities");
	const manifest = save("authorization", { operationDigest: operation.digest, trust: operation.trust,
		bootstrapEnvironment: environment, reportingEnvironment: reporting, capabilities,
		provider: safe ? "none" : catalog.sources[profile.sources[0]]?.provider || "unknown",
		credentialAliases: {
			appId: alias(bindings, "app_id", "vars"),
			appKey: alias(bindings, "app_private_key", "secrets"),
			bootstrapToken: alias(bindings, "bootstrap_token", "secrets"),
			reportAppId: alias(reportBindings, "app_id", "vars"),
			reportAppKey: alias(reportBindings, "app_private_key", "secrets"),
		},
	});
	output({ environment, reporting_environment: reporting,
		app_id_name: manifest.credentialAliases.appId, app_key_name: manifest.credentialAliases.appKey,
		bootstrap_token_name: manifest.credentialAliases.bootstrapToken,
		report_app_id_name: manifest.credentialAliases.reportAppId,
		report_app_key_name: manifest.credentialAliases.reportAppKey });
}
function generate() {
	const operation = loadOperation();
	const authorization = read("authorization", process.env.CI_AUTHORIZATION_DIGEST);
	assert(authorization.operationDigest === operation.digest, "Authorization refers to a different operation");
	fs.mkdirSync(GENERATED, { recursive: true });
	const branch = operation.mode === "generated"
		? C.safeRef(operation.branchPrefix + (process.env.GITHUB_RUN_ID || "1") + "-" + (process.env.GITHUB_RUN_ATTEMPT || "1"))
		: null;
	let tasks;
	if (operation.mode === "readonly") {
		tasks = operation.checks;
		graph(tasks);
		const jobs = {};
		for (const task of tasks) {
			jobs["check_" + task.id.replaceAll("-", "_")] = {
				name: task.id, "runs-on": "ubuntu-latest", permissions: { contents: "read" },
				...(task.needs.length ? { needs: task.needs.map(id => "check_" + id.replaceAll("-", "_")) } : {}),
				steps: [
					{ uses: "actions/checkout@v7", with: { "persist-credentials": false } },
					{ uses: "actions/setup-node@v7.1.0", with: { "node-version": 24 } },
					{ name: "Execute " + task.id, run: "node ci/controller/stages.cjs check " + task.id },
				],
			};
		}
		fs.writeFileSync(path.join(GENERATED, "pipeline.yml"), JSON.stringify({
			name: "Configured validation pipeline", on: { workflow_dispatch: {} }, permissions: {}, jobs,
		}, null, 2) + "\n");
	} else {
		assert(operation.trust.level === "trusted-source", "Cannot generate privileged pipeline from PR");
		const args = ["dependencies/packages/core/dependencyLoader/index.ts", "--exec",
			"luau.lute", "run", "ci/bootstrap/generateWorkflows.luau", GENERATED];
		command("node", args, { env: {
			...process.env, CI_EVENT: eventForPlan(operation), CI_OPERATION: "build", CI_OPERATION_PLAN: operation.plan,
			CI_SELECTED_COMPONENTS: JSON.stringify(operation.components),
			CI_PUBLICATION_ENABLED: String(operation.publication),
			CI_EXECUTION_PREFIX: operation.branchPrefix, CI_GENERATED_BRANCH: branch,
		}, timeout: 240000 });
		const discovered = fs.readdirSync(GENERATED).filter(file => file.endsWith(".yml"));
		assert(discovered.includes("pipeline.yml"), "Luau generator did not produce pipeline.yml");
		tasks = discovered.map(name => ({ id: name, kind: "workflow", needs: [] }));
	}
	const files = fs.readdirSync(GENERATED).filter(file => file.endsWith(".yml")).sort();
	assert(files.includes("pipeline.yml"), "Missing generated pipeline");
	// Lock the workflow under the exact path GitHub will execute, not its temporary artifact path.
	// The detached worktree is never published by the generator.
	const offlineReadonly = process.env.ACT === "true" && operation.mode === "readonly";
	if (!offlineReadonly) {
	const lockWorktree = fs.mkdtempSync(path.join(os.tmpdir(), "ci-generated-lock-"));
	fs.rmSync(lockWorktree, { recursive: true, force: true });
	let attached = false;
	try {
		command("git", ["worktree", "add", "--detach", lockWorktree, operation.trust.sha], { timeout: 120000 });
		attached = true;
		const loader = path.join(ROOT, "dependencies/packages/core/dependencyLoader/index.ts");
		for (const filename of files) {
			const staged = path.join(lockWorktree, ".github/workflows", filename);
			mkdir(staged);
			fs.copyFileSync(path.join(GENERATED, filename), staged);
		}
		for (const filename of files) {
			const workflow = ".github/workflows/" + filename;
			for (const flags of [["--no-interactive", "--no-narrow"], ["--verify-local"]]) {
				command("node", [loader, "--exec", "tools.actionsLock", ...flags, workflow],
					{ cwd: lockWorktree, timeout: 180000 });
			}
		}
		const locked = path.join(lockWorktree, ".github/workflows/actions.lock");
		assert(fs.existsSync(locked), "Generated workflow lockfile missing");
		fs.copyFileSync(locked, path.join(GENERATED, "actions.lock"));
	} finally {
		if (attached) command("git", ["worktree", "remove", "--force", lockWorktree], { timeout: 30000 });
	}
	command("bash", ["ci/bootstrap/check-workflows.sh", GENERATED], { timeout: 240000 });
	} else {
		// Local act has no GitHub token. This pipeline runs directly as commands, not hosted Actions.
		// Never skip action locking for a pipeline that might be dispatched to GitHub.
		console.log("::notice::Local read-only act run: hosted workflow locking and actionlint deferred to hosted CI");
	}
	const hashes = {};
	for (const filename of [...files, ...(offlineReadonly ? [] : ["actions.lock"])]) {
		assert(/^[a-z][a-z0-9-]*\.yml$/.test(filename) || filename === "actions.lock", "Invalid generated filename");
		if (filename.endsWith(".yml")) {
			const source = fs.readFileSync(path.join(GENERATED, filename), "utf8").replace(/^#.*\n/, "");
			JSON.parse(source); // The Luau emitter generates JSON, which is valid YAML.
		}
		hashes[filename] = fileHash(path.join(GENERATED, filename));
	}
	assert(files.includes("pipeline.yml"), "Missing generated pipeline");
	const manifest = save("pipeline", { trust: operation.trust, operationDigest: operation.digest,
		authorizationDigest: authorization.digest, branch, transport: operation.mode === "readonly" ? "local" : "hosted",
		tasks, files: hashes });
	output({ mode: operation.mode, branch: branch || "" });
	console.log("Generated " + files.length + " pipeline workflow file(s) at digest " + manifest.digest);
}
function scrubbedEnvironment() {
	const env = { ...process.env, CI_EVENT: "pull_request", CI_OPERATION: "validation" };
	for (const key of Object.keys(env)) {
		if (key === "GH_TOKEN" || key === "GITHUB_TOKEN" || key.startsWith("CI_CREDENTIAL_") ||
			key.startsWith("ACTIONS_ID_TOKEN_") || key === "CI_SECRETS" || key === "CI_VARIABLES") delete env[key];
	}
	return env;
}
function executeCheck(task) {
	assert(task.kind === "command" && Array.isArray(task.command) && task.command.length,
		"Invalid command component");
	const env = scrubbedEnvironment();
	const result = spawnSync(task.command[0], task.command.slice(1), { cwd: ROOT, env,
		encoding: "utf8", timeout: task.timeoutSeconds * 1000, maxBuffer: 24 * 1024 * 1024 });
	return { state: result.status === 0 && !result.error ? "passed" : "failed",
		code: result.status, message: (result.error?.message || result.stderr || "").slice(-1500),
		stdout: result.stdout || "", stderr: result.stderr || "" };
}
function check(name) {
	assert(/^[a-z][a-z0-9-]*$/.test(name), "Invalid component name");
	const { readConfig } = require("../bootstrap/routes.cjs");
	const entry = readConfig().checks[name];
	assert(entry, "Unknown check component");
	const result = executeCheck({ id: name, kind: "command", command: entry.command, timeoutSeconds: entry.timeoutSeconds });
	process.stdout.write(result.stdout);
	process.stderr.write(result.stderr);
	if (result.state !== "passed") process.exitCode = 1;
}
async function runLocal(tasks) {
	const order = graph(tasks);
	const outcomes = Object.create(null);
	fs.mkdirSync(LOGS, { recursive: true });
	// Promise-based scheduler permits independent components to run concurrently.
	const pending = new Map();
	for (const id of order) {
		const task = tasks.find(item => item.id === id);
		pending.set(id, Promise.all(task.needs.map(required => pending.get(required))).then(async () => {
			if (task.needs.some(required => outcomes[required].state !== "passed")) {
				outcomes[id] = { state: "blocked", reason: "Required component failed" };
				return;
			}
			// Run in a child process so expensive checks do not serialize independent components.
			const filename = path.join(LOGS, id.replaceAll("/", "_") + ".log");
			const result = await new Promise(resolve => {
				const child = spawn(task.command[0], task.command.slice(1), { cwd: ROOT, env: scrubbedEnvironment(), stdio: ["ignore", "pipe", "pipe"] });
				let diagnostic = "";
				const stream = fs.createWriteStream(filename);
				const timer = setTimeout(() => child.kill("SIGKILL"), task.timeoutSeconds * 1000);
				for (const source of [child.stdout, child.stderr]) {
					source?.on("data", data => { stream.write(data); diagnostic = (diagnostic + data.toString()).slice(-1500); });
				}
				child.on("error", error => { diagnostic = error.message; });
				child.on("close", (code, signal) => {
					clearTimeout(timer);
					stream.end();
					resolve({ state: signal === "SIGKILL" ? "cancelled" : code === 0 ? "passed" : "failed", code, signal, message: diagnostic });
				});
			});
			outcomes[id] = result;
			console.log("::notice::" + id + " " + result.state);
		}));
	}
	await Promise.all(pending.values());
	return { status: Object.values(outcomes).every(item => item.state === "passed") ? "passed" : "failed", outcomes };
}
function verifyGenerated(pipeline) {
	for (const [filename, digest] of Object.entries(pipeline.files)) {
		assert(fileHash(path.join(GENERATED, filename)) === digest, "Generated workflow modified: " + filename);
	}
}
async function githubApi(route, token, method = "GET") {
	const base = process.env.GITHUB_API_URL || "https://api.github.com";
	const response = await fetch(base + route, { method, redirect: "error", signal: AbortSignal.timeout(20000),
		headers: { Authorization: "Bearer " + token, Accept: "application/vnd.github+json", "User-Agent": "Template-linear-CI" } });
	if (!response.ok) throw new Error("GitHub API " + method + " " + route.split("?")[0] + ": HTTP " + response.status);
	return response.status === 204 ? null : response.json();
}
async function getBootstrapToken() {
	const appId = process.env.CI_CREDENTIAL_APP_ID;
	const key = process.env.CI_CREDENTIAL_APP_PRIVATE_KEY;
	if (appId && key) {
		const directory = fs.mkdtempSync(path.join(os.tmpdir(), "ci-app-"));
		const filename = path.join(directory, "key.pem");
		try {
			fs.writeFileSync(filename, key, { mode: 0o600 });
			const source = command("node", ["ci/github/authentication/signAppJwt.cjs",
				appId, filename, context().repository, JSON.stringify({ contents: "write", workflows: "write" }), ""], { timeout: 60000 });
			const access = JSON.parse(source);
			assert(typeof access.token === "string" && access.token, "App exchange did not return token");
			console.log("::add-mask::" + access.token);
			return access.token;
		} finally { fs.rmSync(directory, { recursive: true, force: true }); }
	}
	const token = process.env.CI_CREDENTIAL_BOOTSTRAP_TOKEN;
	assert(token && token !== process.env.GH_TOKEN, "No environment-backed bootstrap credential available");
	console.log("::add-mask::" + token);
	return token;
}
function gitPush(args, token) {
	const directory = fs.mkdtempSync(path.join(os.tmpdir(), "ci-git-"));
	const askpass = path.join(directory, "askpass.sh");
	try {
		fs.writeFileSync(askpass, '#!/bin/sh\ncase "$1" in *Username*) printf x-access-token ;; *Password*) printf %s "$CI_EXECUTION_TOKEN" ;; esac\n', { mode: 0o700 });
		return command("git", args, { env: { ...process.env, GIT_ASKPASS: askpass,
			GIT_TERMINAL_PROMPT: "0", CI_EXECUTION_TOKEN: token }, timeout: 120000 });
	} finally { fs.rmSync(directory, { recursive: true, force: true }); }
}
async function launchHosted(pipeline, operation) {
	assert(operation.trust.level === "trusted-source" && pipeline.transport === "hosted", "Untrusted code cannot launch hosted branches");
	assert(process.env.GITHUB_REF === "refs/heads/source" && process.env.GITHUB_EVENT_NAME !== "pull_request", "Trusted source branch required");
	const token = await getBootstrapToken();
	const workspace = fs.mkdtempSync(path.join(os.tmpdir(), "ci-worktree-"));
	fs.rmSync(workspace, { recursive: true, force: true });
	const remote = (process.env.GITHUB_SERVER_URL || "https://github.com") + "/" + operation.trust.repository + ".git";
	assert(remote.startsWith("https://github.com/"), "Untrusted Git remote");
	let added = false;
	try {
		command("git", ["worktree", "add", "--detach", workspace, operation.trust.sha]);
		added = true;
		for (const filename of Object.keys(pipeline.files)) {
			const destination = path.join(workspace, ".github/workflows", filename);
			mkdir(destination);
			fs.copyFileSync(path.join(GENERATED, filename), destination);
		}
		command("git", ["add", "--", ".github/workflows"], { cwd: workspace });
		command("git", ["-c", "user.name=CI controller", "-c", "user.email=ci-controller@users.noreply.github.com",
			"-c", "core.hooksPath=/dev/null", "commit", "--no-gpg-sign", "-m", "Generated execution pipeline"], { cwd: workspace });
		const revision = command("git", ["rev-parse", "HEAD"], { cwd: workspace });
		gitPush(["-c", "credential.helper=", "push", remote, "HEAD:refs/heads/" + pipeline.branch], token);
		return { revision, branch: pipeline.branch };
	} finally {
		if (added) command("git", ["worktree", "remove", "--force", workspace]);
	}
}
async function waitForHosted(branch, revision, source) {
	const token = process.env.GH_TOKEN;
	assert(token, "Run observation requires read-only Actions API token");
	const prefix = "/repos/" + source.repository + "/actions/runs";
	let id = null;
	const start = Date.now();
	while (Date.now() - start < 3600000) {
		const data = await githubApi(id ? prefix + "/" + id : prefix + "?branch=" + encodeURIComponent(branch) + "&event=push&per_page=30", token);
		const runs = id ? [data] : data.workflow_runs;
		for (const item of runs) {
			if (item.head_branch !== branch || item.head_sha !== revision ||
				!String(item.path).startsWith(".github/workflows/pipeline.yml")) continue;
			id = item.id;
			if (item.status === "completed") return { runId: id, conclusion: item.conclusion, url: item.html_url };
		}
		if (!id && Date.now() - start > 120000) fail("Generated pipeline was not scheduled");
		await new Promise(resolve => setTimeout(resolve, 8000));
	}
	fail("Generated pipeline timed out before completion");
}
async function runPipeline() {
	const operation = loadOperation();
	const auth = read("authorization", process.env.CI_AUTHORIZATION_DIGEST);
	const pipeline = read("pipeline", process.env.CI_PIPELINE_DIGEST);
	assert(pipeline.operationDigest === operation.digest && pipeline.authorizationDigest === auth.digest, "Pipeline plan provenance mismatch");
	verifyGenerated(pipeline);
	const record = { trust: operation.trust, pipelineDigest: pipeline.digest, state: "failed", transport: pipeline.transport,
		...(pipeline.branch ? { branch: pipeline.branch } : {}) };
	let failure = null;
	try {
		if (pipeline.transport === "local") {
			assert(operation.trust.level === "untrusted" || operation.mode === "readonly", "Invalid local transport");
			Object.assign(record, await runLocal(pipeline.tasks));
			record.state = record.status === "passed" ? "completed" : "failed";
		} else {
			save("execution", record); // Record the owned branch before attempting its launch.
			Object.assign(record, await launchHosted(pipeline, operation));
			save("execution", record); // Preserve ref ownership if monitoring fails.
			Object.assign(record, await waitForHosted(record.branch, record.revision, operation.trust));
			record.state = record.conclusion === "success" ? "completed" : "failed";
		}
	} catch (error) {
		failure = String(error.message || error);
		record.reason = failure;
	} finally {
		save("execution", record);
	}
	if (failure || record.state !== "completed") fail("Generated pipeline did not complete: " + (failure || record.conclusion || "component failure"));
}
async function collect() {
	const operation = loadOperation();
	let execution = null;
	const errors = [];
	try { execution = read("execution", process.env.CI_EXECUTION_DIGEST); }
	catch (error) { errors.push("Execution manifest unavailable: " + error.message); }
	const details = { operationDigest: operation.digest, executionDigest: execution?.digest || null,
		executionState: execution?.state || "missing", outcomes: execution?.outcomes || {},
		runId: execution?.runId || null, reporting: "not-requested", errors };
	fs.mkdirSync(STATE, { recursive: true });
	if (execution?.runId && process.env.GH_TOKEN) {
		try {
			const jobs = await githubApi("/repos/" + operation.trust.repository + "/actions/runs/" + execution.runId + "/jobs?per_page=100", process.env.GH_TOKEN);
			details.jobs = jobs.jobs.map(job => ({ id: job.id, name: job.name, conclusion: job.conclusion }));
			const artifacts = await githubApi("/repos/" + operation.trust.repository + "/actions/runs/" + execution.runId + "/artifacts?per_page=100", process.env.GH_TOKEN);
			details.artifacts = artifacts.artifacts.map(item => ({ id: item.id, name: item.name, expired: item.expired }));
			details.reporting = "observed";
		} catch (error) {
			errors.push("Reporting failed: " + error.message);
			details.reporting = "failed";
		}
	}
	// A failed pipeline can be collected successfully; the final gate judges its conclusion separately.
	const state = execution && !errors.length ? "passed" : "failed";
	save("results", { ...details, state });
	const summary = path.join(STATE, "report.md");
	fs.writeFileSync(summary, "# CI execution\n\nOperation: " + operation.name +
		"\n\nExecution: " + details.executionState + "\n\nReporting: " + details.reporting +
		"\n\n" + errors.map(error => "- " + error).join("\n") + "\n");
	if (state !== "passed") process.exitCode = 1;
}
async function cleanup() {
	const operation = loadOperation();
	let execution;
	try { execution = read("execution", process.env.CI_EXECUTION_DIGEST); } catch { /* launch may have failed before recording */ }
	const record = { operationDigest: operation.digest, executionDigest: execution?.digest || null, state: "passed", removed: false };
	try {
		if (execution?.branch) {
			assert(operation.trust.level === "trusted-source" && execution.trust.sha === operation.trust.sha, "Ref ownership mismatch");
			assert(execution.branch === operation.branchPrefix + (process.env.GITHUB_RUN_ID || "") + "-" +
				(process.env.GITHUB_RUN_ATTEMPT || "1"), "Ref outside run namespace");
			assert(/^[a-f0-9]{40}$/.test(execution.revision), "Missing expected generated revision");
			assert(process.env.GH_TOKEN, "Cannot verify owned branch without Actions read token");
			const current = await githubApi("/repos/" + operation.trust.repository + "/git/ref/heads/" +
				execution.branch.split("/").map(encodeURIComponent).join("/"), process.env.GH_TOKEN);
			assert(current.object.sha === execution.revision, "Temporary branch moved; refusing deletion");
			const token = await getBootstrapToken();
			const remote = "https://github.com/" + operation.trust.repository + ".git";
			gitPush(["-c", "credential.helper=", "push", remote, ":refs/heads/" + execution.branch], token);
			record.removed = true;
		}
	} catch (error) {
		record.state = "failed";
		record.reason = String(error.message || error);
	}
	save("cleanup", record);
	if (record.state !== "passed") process.exitCode = 1;
}
function validate() {
	const errors = [];
	const manifests = {};
	for (const kind of ["operation", "authorization", "pipeline", "execution", "results", "cleanup"]) {
		try { manifests[kind] = read(kind); } catch (error) { errors.push(kind + ": " + error.message); }
	}
	if (manifests.operation && manifests.authorization && manifests.authorization.operationDigest !== manifests.operation.digest) errors.push("Operation authorization mismatch");
	if (manifests.pipeline && manifests.authorization && manifests.pipeline.authorizationDigest !== manifests.authorization.digest) errors.push("Pipeline authorization mismatch");
	if (manifests.pipeline && manifests.execution && manifests.execution.pipelineDigest !== manifests.pipeline.digest) errors.push("Executed pipeline digest mismatch");
	if (manifests.execution && (manifests.execution.state !== "completed" ||
		(manifests.execution.transport === "hosted" && manifests.execution.conclusion !== "success"))) errors.push("Pipeline execution did not complete successfully");
	if (manifests.results?.state !== "passed") errors.push("Results were not successfully collected");
	if (manifests.results && manifests.execution && manifests.results.executionDigest !== manifests.execution.digest) errors.push("Collected results do not match the executed pipeline");
	if (manifests.cleanup && manifests.execution && manifests.cleanup.executionDigest !== manifests.execution.digest) errors.push("Cleanup refers to a different execution");
	if (manifests.cleanup?.state !== "passed") errors.push("Cleanup failed or was not recorded");
	errors.push(...C.validateJobConclusions(process.env, process.env.ACT === "true"));
	if (manifests.pipeline?.transport === "local" && manifests.execution?.outcomes) {
		errors.push(...C.validateOutcomes(manifests.pipeline.tasks, manifests.execution.outcomes));
	}
	if (errors.length) {
		for (const error of errors) console.error("::error::" + error);
		process.exitCode = 1;
	} else console.log("::notice::Completed generated pipeline and all controller stages");
}
async function main() {
	const [stage, name] = process.argv.slice(2);
	switch (stage) {
		case "setup": stageToolchain(); break;
		case "restore": restore(); break;
		case "resolve": resolveOperation(); break;
		case "authorize": checkPermissions(); break;
		case "generate": generate(); break;
		case "run": await runPipeline(); break;
		case "collect": await collect(); break;
		case "cleanup": await cleanup(); break;
		case "validate": validate(); break;
		case "check": check(name); break;
		default: fail("Unknown CI controller stage: " + stage);
	}
}
if (require.main === module) main().catch(error => {
	console.error("::error::" + String(error.message || error).replace(/[\r\n]+/g, " "));
	process.exitCode = 1;
});
module.exports = { stageToolchain, restore, resolveOperation, checkPermissions, generate, runLocal, runPipeline,
	collect, cleanup, validate, executeCheck };
