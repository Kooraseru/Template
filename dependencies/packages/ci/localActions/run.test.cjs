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
