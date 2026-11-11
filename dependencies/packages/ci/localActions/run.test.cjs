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
