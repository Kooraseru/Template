"use strict";
const test = require("node:test");
const assert = require("node:assert/strict");
const fs = require("node:fs");
const os = require("node:os");
const path = require("node:path");
const { documentOperation, getStatus } = require("./workspace.cjs");
const ci = require("./ci.cjs");

test("write authorization fails before connecting; read capabilities cannot dispatch arbitrary bridge calls", async () => {
	const connectBridge = () => { throw new Error("must not connect"); };
	await assert.rejects(documentOperation({ root: ".", operation: "applyEdit", args: { authorize: true }, allowWrites: false, connectBridge }), /WRITE_NOT_AUTHORIZED/);
	await assert.rejects(documentOperation({ root: ".", operation: "applyEdit", args: {}, allowWrites: true, connectBridge }), /WRITE_NOT_AUTHORIZED/);
	await assert.rejects(documentOperation({ root: ".", operation: "executeCommand", args: {}, connectBridge }), /UNSUPPORTED_CAPABILITY/);
});

test("document tools close the selected connection and return the bridge buffer snapshot", async () => {
	let closed = false;
	const bridge = { loadModule: async args => { assert.match(args.path, /editorIntegration\/documents.cjs$/); return "module"; },
		call: async args => { assert.deepEqual(args.path, ["getDocument"]); assert.equal(args.args[0].file, "source/example.txt"); return "ref"; },
		snapshot: async () => ({ text: "unsaved", version: 2, dirty: true }), close: () => { closed = true; } };
	const result = await documentOperation({ root: ".", operation: "getDocument", args: { file: "source\\example.txt" }, connectBridge: async () => bridge });
	assert.equal(result.dirty, true); assert.equal(closed, true);
});

test("disconnected and ambiguous sessions fail with a selection action", async () => {
	for (const message of ["No session", "Multiple matching sessions"]) {
		await assert.rejects(documentOperation({ root: ".", operation: "getDocument", args: { file: "file.txt" }, connectBridge: async () => { throw new Error(message); } }), /WORKBENCH_BRIDGE_SESSION/);
	}
});

test("status distinguishes unavailable diagnostics, absent CI, failures and corrupt records", async t => {
	const root = fs.mkdtempSync(path.join(os.tmpdir(), "workspace-status-"));
	t.after(() => fs.rmSync(root, { recursive: true, force: true }));
	const status = await getStatus({ root, problems: async () => { throw new Error("ambiguous session"); } });
	assert.equal(status.editor.connected, false); assert.equal(status.diagnostics.available, false);
	assert.equal(status.dependencies.available, false); assert.equal(status.ci.available, false);
	const directory = path.join(root, ".workspace/ci/runs"); fs.mkdirSync(directory, { recursive: true });
	fs.writeFileSync(path.join(directory, "abcd.json"), JSON.stringify({ version: 1, runner: "act", startedAt: "2026-11-10T12:00:00Z", state: "failed", exitCode: 1, failure: "recorded failure" }));
	fs.writeFileSync(path.join(directory, "eeee.json"), "corrupt");
	const result = ci.getStatus({ root });
	assert.equal(result.available, true); assert.equal(result.executions[0].state, "failed");
	assert.equal(result.executions[0].failure, "recorded failure"); assert.ok(result.issues.some(issue => issue.includes("eeee.json")));
});

test("status reads v2 stage outcomes without claiming local Publish completed", async t => {
	const root = fs.mkdtempSync(path.join(os.tmpdir(), "workspace-pipeline-")); t.after(() => fs.rmSync(root, { recursive: true, force: true }));
	const directory = path.join(root, ".workspace/ci/runs"); fs.mkdirSync(directory, { recursive: true });
	fs.writeFileSync(path.join(directory, "abcd.json"), JSON.stringify({ version: 2, runner: "act", startedAt: "2026-11-11T12:00:00Z", state: "failed", operation: "build", source: "a".repeat(40), stages: { start: "passed", build: "passed", export: "failed", publish: "disabled" }, failureStage: "export" }));
	const result = ci.getStatus({ root }); assert.equal(result.executions[0].scope, "pipeline"); assert.equal(result.executions[0].stages.build, "passed"); assert.equal(result.executions[0].stages.publish, "disabled"); assert.equal(result.executions[0].failureStage, "export"); assert.equal(result.executions[0].currentCheckout, null);
});
