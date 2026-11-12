"use strict";
const test = require("node:test");
const assert = require("node:assert/strict");
const fs = require("node:fs");
const os = require("node:os");
const path = require("node:path");
const { activate } = require("./documents.cjs");

function fixture(t) {
	const root = fs.mkdtempSync(path.join(os.tmpdir(), "workspace-document-"));
	t.after(() => fs.rmSync(root, { recursive: true, force: true }));
	fs.writeFileSync(path.join(root, "example.txt"), "saved");
	let text = "unsaved 🧡 text";
	const document = { uri: { fsPath: path.join(root, "example.txt") }, version: 7, isDirty: true, languageId: "plaintext", getText: () => text, positionAt: offset => offset };
	let applied = 0;
	const vscode = {
		Uri: { file: fsPath => ({ fsPath }) },
		Range: class { constructor(start, end) { this.start = start; this.end = end; } },
		WorkspaceEdit: class { changes = []; replace(uri, range, text) { this.changes.push({ uri, range, text }); } },
		workspace: { isTrusted: true, openTextDocument: async () => document,
			applyEdit: async edit => { applied++; for (const change of edit.changes.reverse()) text = text.slice(0, change.range.start) + change.text + text.slice(change.range.end); document.version++; return true; } },
	};
	return { api: activate({ vscode, workspaceFolder: { uri: { fsPath: root } } }), vscode, root, document, applied: () => applied };
}

test("document reads return unsaved buffers with UTF-16 pagination and version", async t => {
	const { api } = fixture(t);
	const result = await api.getDocument({ file: "example.txt", offset: 8, limit: 2 });
	assert.equal(result.text, "🧡");
	assert.equal(result.version, 7); assert.equal(result.dirty, true); assert.equal(result.truncated, true);
});

test("authorized edits use the current version, update the buffer and never save", async t => {
	const { api, root, applied } = fixture(t);
	const result = await api.applyEdit({ file: "example.txt", version: 7, authorize: true, edits: [{ start: 0, end: 7, text: "changed" }] });
	assert.equal(result.version, 8); assert.equal(result.saved, false); assert.equal(applied(), 1);
	assert.equal((await api.getDocument({ file: "example.txt" })).text, "changed 🧡 text");
	assert.equal(fs.readFileSync(path.join(root, "example.txt"), "utf8"), "saved");
});

test("rejects stale, unauthorized, overlapping and out-of-bounds edits without mutation", async t => {
	const { api, applied, vscode } = fixture(t);
	const input = { file: "example.txt", version: 7, authorize: true, edits: [{ start: 0, end: 1, text: "x" }] };
	await assert.rejects(api.applyEdit({ ...input, version: 6 }), /VERSION_CONFLICT/);
	await assert.rejects(api.applyEdit({ ...input, authorize: false }), /WRITE_NOT_AUTHORIZED/);
	await assert.rejects(api.applyEdit({ ...input, edits: [{ start: 0, end: 8, text: "x" }, { start: 2, end: 9, text: "x" }] }), /INVALID_EDIT/);
	await assert.rejects(api.applyEdit({ ...input, edits: [{ start: 0, end: 999, text: "x" }] }), /INVALID_EDIT/);
	vscode.workspace.isTrusted = false;
	await assert.rejects(api.applyEdit(input), /UNTRUSTED_WORKSPACE/);
	assert.equal(applied(), 0);
});

test("document operations reject Windows escapes and private workspace state", async t => {
	const { api } = fixture(t);
	for (const file of ["../escape", "..\\escape", "C:\\secret", "\\\\server\\share", "\\rooted", ".workspace/session.json", "dependencies/managed/bin/tool", ".git/config"]) {
		await assert.rejects(api.getDocument({ file }), /INVALID_FILE/);
	}
});

test("VS Code rejections produce an actionable failure", async t => {
	const { api, vscode } = fixture(t); vscode.workspace.applyEdit = async () => false;
	await assert.rejects(api.applyEdit({ file: "example.txt", version: 7, authorize: true, edits: [{ start: 0, end: 0, text: "x" }] }), /EDIT_REJECTED/);
});

test("real path boundaries reject links outside the workspace and into private state", async t => {
	const { api, root } = fixture(t);
	const outside = fs.mkdtempSync(path.join(os.tmpdir(), "document-outside-"));
	t.after(() => fs.rmSync(outside, { recursive: true, force: true }));
	fs.writeFileSync(path.join(outside, "secret.txt"), "private");
	fs.mkdirSync(path.join(root, ".workspace")); fs.writeFileSync(path.join(root, ".workspace/secret.txt"), "private");
	fs.symlinkSync(outside, path.join(root, "outside"), process.platform === "win32" ? "junction" : "dir");
	fs.symlinkSync(path.join(root, ".workspace"), path.join(root, "private"), process.platform === "win32" ? "junction" : "dir");
	await assert.rejects(api.getDocument({ file: "outside/secret.txt" }), /INVALID_FILE/);
	await assert.rejects(api.getDocument({ file: "private/secret.txt" }), /INVALID_FILE/);
});
