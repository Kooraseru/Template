"use strict";
const assert = require("node:assert/strict");
const fs = require("node:fs");
const os = require("node:os");
const path = require("node:path");
const { spawnSync } = require("node:child_process");
const test = require("node:test");
const root = path.resolve(__dirname, "../../../..");
const lute = path.join(root, "dependencies/managed/bin/lute", process.platform === "win32" ? "lute.exe" : "lute");

// Exercise the real entry before credentials are read or any CI task is executed.
test("hosted publication rejects feature refs while local ACT accepts the checkout", t => {
	const temporary = fs.mkdtempSync(path.join(os.tmpdir(), "local-act-gate-"));
	t.after(() => fs.rmSync(temporary, { recursive: true, force: true }));
	for (const [act, ref, allowed] of [["", "refs/heads/feature", false], ["", "refs/heads/source", true], ["true", "refs/heads/feature", true]]) {
		const result = spawnSync(lute, ["run", "ci/entry.luau", "--credential-provider"], {
			cwd: root, encoding: "utf8", timeout: 15000, windowsHide: true,
			env: { ...process.env, ACT: act, GITHUB_ACTIONS: "true", GITHUB_EVENT_NAME: "workflow_dispatch", GITHUB_REF: ref,
				CI_PROFILE: "source-ci", CI_EVENT: "workflow_dispatch", GITHUB_TOKEN: "", GH_TOKEN: "", CI_GRAPH_RUN: "true", GITHUB_OUTPUT: path.join(temporary, "output") },
		});
		assert.ifError(result.error);
		if (allowed) assert.equal(result.status, 0, result.stdout + result.stderr);
		else { assert.notEqual(result.status, 0); assert.match(result.stdout, /unavailable for this event and ref/); }
	}
});

test("local launcher selects safe defaults and respects explicit operations and events", () => {
	const { options } = require("./run.cjs");
	assert.equal(options([]).event, "workflow_dispatch"); assert.equal(options([]).operation, "validation");
	assert.equal(options(["push"]).operation, "build"); assert.equal(options(["--input", "operation=build"]).operation, "build");
	assert.equal(options(["--workflows", "push", "--input=operation=readiness"]).operation, "readiness");
	assert.equal(options(["--actor", "push"]).event, "workflow_dispatch");
	assert.equal(options(["--list"]).informational, true);
	assert.throws(() => options(["pull_request", "--input", "operation=build"]), /Validation only/);
	assert.throws(() => options(["--input", "operation=anything"]), /Unknown/);
});

test("dotenv input files and event payload operation are respected", t => {
	const { options } = require("./run.cjs"), temporary = fs.mkdtempSync(path.join(os.tmpdir(), "act-inputs-")); t.after(() => fs.rmSync(temporary, { recursive: true, force: true }));
	const input = path.join(temporary, "inputs"), event = path.join(temporary, "event.json"); fs.writeFileSync(input, "# inputs\noperation='build'\n"); fs.writeFileSync(event, JSON.stringify({ inputs: { operation: "readiness" } }));
	assert.equal(options(["--input-file", input]).operation, "build"); assert.equal(options(["--eventpath", event]).operation, "readiness"); assert.equal(options(["--input-file", input, "--input", "operation=validation"]).operation, "validation");
});


test("local CI adapts the disposable single-launcher copy", t => {
	const { prepareStagedWorkflow, stagedEventArguments, options } = require("./run.cjs");
	const directory = fs.mkdtempSync(path.join(os.tmpdir(), "staged-ci-"));
	t.after(() => fs.rmSync(directory, { recursive: true, force: true }));
	const source = fs.readFileSync(path.join(root, ".github/workflows/ci.yml"), "utf8");
	const file = path.join(directory, "ci.yml");
	fs.writeFileSync(file, source);
	assert.equal(prepareStagedWorkflow(file, "local-fixture"), false);
	const actual = fs.readFileSync(file, "utf8");
	assert.match(actual, /actions\/upload-artifact@v4/);
	assert.match(actual, /node ci\/bootstrap\/routes\.cjs resolve/);
	assert.match(actual, /name: Start Generated CI/);
	assert.doesNotMatch(actual, /actions\/upload-artifact@v7/);
	assert.doesNotMatch(actual, /^  publish-(general|projects|rulesets):/m);
	assert.equal(fs.readFileSync(path.join(root, ".github/workflows/ci.yml"), "utf8"), source);
	const args = ["--workflows", ".github/workflows/ci.yml", "--secret-file", ""];
	assert.equal(stagedEventArguments(args, options(args))[0], "pull_request");
	assert.equal(stagedEventArguments(["push"], options(["push"]))[0], "push");
});

test("local act wrapper streams output and bounds worktree teardown", () => {
	const source = fs.readFileSync(path.join(__dirname, "run.cjs"), "utf8");
	assert.match(source, /async function main/);
	assert.match(source, /child\.stdout, process\.stdout/);
	assert.match(source, /child\.stderr, process\.stderr/);
	assert.match(source, /timeout: 30_000/);
});


test("file arguments work in both direct and staged local workflows", () => {
	const { resolveFileArguments } = require("./run.cjs");
	const directory = path.join(os.tmpdir(), "local-act-paths");
	assert.deepEqual(resolveFileArguments(["--input-file", "inputs.env", "--eventpath=event.json", "--secret-file=secrets.env", "-e", "payload.json", "--var-file", ""], directory), [
		"--input-file", path.resolve(directory, "inputs.env"), "--eventpath=" + path.resolve(directory, "event.json"),
		"--secret-file=" + path.resolve(directory, "secrets.env"), "-e", path.resolve(directory, "payload.json"), "--var-file", "",
	]);
});

test("local stages have a configurable bounded timeout", () => {
	const { timeoutMilliseconds } = require("./run.cjs");
	assert.equal(timeoutMilliseconds({}), 30 * 60_000);
	assert.equal(timeoutMilliseconds({ CI_LOCAL_TIMEOUT_MINUTES: "45" }), 45 * 60_000);
	for (const value of ["0", "-1", "abc", "241", "1.5"]) assert.throws(() => timeoutMilliseconds({ CI_LOCAL_TIMEOUT_MINUTES: value }), /1 to 240/);
});

test("local artifact server configuration is isolated per run", () => {
	const configuration = fs.readFileSync(path.join(root, ".vscode/config/act/actrc"), "utf8");
	assert.doesNotMatch(configuration, /--artifact-server-(?:path|port)/);
	const launcher = fs.readFileSync(path.join(__dirname, "run.cjs"), "utf8");
	assert.match(launcher, /"--artifact-server-path", transport/);
});

test("failed commands propagate exit codes and retain the stage log", { skip: process.platform === "win32" }, t => {
	const temporary = fs.mkdtempSync(path.join(os.tmpdir(), "ci-failing-command-"));
	const runId = "forced-failure-" + process.pid + "-" + Date.now();
	const runDirectory = path.join(root, "build/run", runId);
	t.after(() => { fs.rmSync(temporary, { recursive: true, force: true }); fs.rmSync(runDirectory, { recursive: true, force: true }); });
	fs.writeFileSync(path.join(temporary, "node"), "#!/bin/sh\nprintf 'intentional failure\\n'\nexit 42\n", { mode: 0o755 });
	const result = spawnSync("bash", ["ci/github/workflows/run-logged.sh", "build", "forced-failure"], {
		cwd: root, encoding: "utf8", timeout: 20_000, windowsHide: true,
		env: { ...process.env, PATH: temporary + path.delimiter + (process.env.PATH || ""), CI_RUN_ID: runId, CI_LOCAL_RUN_ID: runId },
	});
	assert.ifError(result.error);
	assert.equal(result.status, 42, result.stdout + result.stderr);
	assert.match(fs.readFileSync(path.join(runDirectory, "build/logs/forced-failure.log"), "utf8"), /intentional failure/);
});
