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


test("staged CI executes directly and adapts only the local workflow copy", t => {
	const { prepareStagedWorkflow, stagedEventArguments, options } = require("./run.cjs");
	const directory = fs.mkdtempSync(path.join(os.tmpdir(), "staged-ci-"));
	t.after(() => fs.rmSync(directory, { recursive: true, force: true }));
	const source = fs.readFileSync(path.join(root, ".github/workflows/ci.yml"), "utf8");
	const file = path.join(directory, "ci.yml");
	// Act transforms a disposable checkout before invoking this suite. Restore the
	// hosted syntax in the fixture so both hosted and local runs test the adapter.
	const fixture = source
		.replace(/^    environment: (ci-(?:projects|rulesets|reporting))\r?$/gm,
			"    environment:\n      name: $1\n      deployment: false")
		.replaceAll("actions/upload-artifact@v4", "actions/upload-artifact@v7")
		.replaceAll("actions/download-artifact@v4", "actions/download-artifact@v8")
		.replace(/build\/run\/[a-f0-9]{8}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{12}\//gi,
			"build/run/" + "$" + "{{ env.CI_RUN_ID }}/");
	fs.writeFileSync(file, fixture);
	assert.equal(prepareStagedWorkflow(file, "local-fixture"), true);
	const actual = fs.readFileSync(file, "utf8");
	assert.match(actual, /environment: ci-projects/);
	assert.match(actual, /environment: ci-rulesets/);
	assert.match(actual, /environment: ci-reporting/);
	assert.doesNotMatch(actual, /deployment: false/);
	assert.match(actual, /actions\/upload-artifact@v4/);
	assert.match(actual, /actions\/download-artifact@v4/);
	assert.match(actual, /build\/run\/local-fixture\/transport\/bundles/);
	assert.match(fixture, /deployment: false/);
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
