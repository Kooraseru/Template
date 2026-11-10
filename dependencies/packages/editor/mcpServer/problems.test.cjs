"use strict";

const test = require("node:test");
const assert = require("node:assert/strict");
const path = require("node:path");
const { getProblems, normalizeFile } = require("./problems.cjs");

const root = path.resolve(__dirname, "../../../..");

test("Problems snapshots are filtered, ordered, and bounded", async () => {
	const samples = [
		{ file: "src/b.ts", line: 8, column: 2, severity: "warning", message: "warning" },
		{ file: "src/a.ts", line: 12, column: 1, severity: "error", message: "second" },
		{ file: "src/a.ts", line: 2, column: 1, severity: "error", message: "first" },
	];
	let closed = false;
	const connectBridge = async options => {
		assert.equal(options.workspace, root);
		return {
			loadModule: async options => {
				assert.equal(options.path, "dependencies/packages/editor/editorIntegration/problems.cjs");
				return { id: "module" };
			},
			call: async () => ({ id: "snapshot" }),
			snapshot: async () => samples,
			close: () => { closed = true; },
		};
	};
	const result = await getProblems({ root, connectBridge, severity: "error", limit: 1 });
	assert.equal(result.total, 2);
	assert.equal(result.counts.error, 2);
	assert.equal(result.counts.warning, 0);
	assert.equal(result.truncated, true);
	assert.deepEqual(result.diagnostics.map(item => item.line), [2]);
	assert.equal(closed, true);
	const fileResult = await getProblems({ root, connectBridge, file: "src/b.ts" });
	assert.equal(fileResult.total, 1);
	assert.equal(fileResult.diagnostics[0].severity, "warning");
});

test("Problems tool rejects escaping paths and invalid limits", async () => {
	assert.equal(normalizeFile("src\\test.ts"), "src/test.ts");
	assert.throws(() => normalizeFile("../secrets"), /inside the workspace/);
	assert.throws(() => normalizeFile("C:\\secrets"), /workspace-relative/);
	await assert.rejects(getProblems({ root, limit: 101 }), /between 1 and 100/);
});

test("Problems tool reports disconnected editor sessions instead of claiming success", async () => {
	await assert.rejects(getProblems({ root, connectBridge: async () => { throw new Error("No matching session"); } }),
		/Live VS Code Problems unavailable: No matching session/);
});
