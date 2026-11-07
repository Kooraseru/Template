"use strict";

const assert = require("node:assert/strict");
const path = require("node:path");
const test = require("node:test");
const { activate } = require("./activate.cjs");

function disposable() { return { dispose() {} }; }
function fixture(root, textDocuments = []) {
	const commands = new Map();
	const watchers = [];
	const statusItems = [];
	const outputLines = [];
	const subscriptions = [];
	const diagnosticCalls = { sets: [], deletes: [], cleared: false };
	const workspace = {
		textDocuments,
		createFileSystemWatcher(pattern) {
			const watcher = { pattern, onDidCreate(callback) { this.create = callback; return disposable(); }, onDidChange(callback) { this.change = callback; return disposable(); }, onDidDelete(callback) { this.delete = callback; return disposable(); }, dispose() {} };
			watchers.push(watcher);
			return watcher;
		},
		onDidSaveTextDocument() { return disposable(); },
		onDidOpenTextDocument(callback) { this.open = callback; return disposable(); },
		onDidChangeTextDocument(callback) { this.change = callback; return disposable(); },
	};
	const vscode = {
		StatusBarAlignment: { Left: 1 },
		DiagnosticSeverity: { Error: 0, Warning: 1, Information: 2 },
		window: {
			createOutputChannel() { return { appendLine(line) { outputLines.push(line); }, show() {}, dispose() {} }; },
			createStatusBarItem() { const item = { show() {}, dispose() {} }; statusItems.push(item); return item; },
		},
		languages: { createDiagnosticCollection() { return { clear() { diagnosticCalls.cleared = true; }, set(uri, items) { diagnosticCalls.sets.push({ uri, items }); }, delete(uri) { diagnosticCalls.deletes.push(uri); }, dispose() {} }; } },
		commands: { registerCommand(name, callback) { commands.set(name, callback); return disposable(); } },
		workspace,
		RelativePattern: class { constructor(folder, glob) { this.folder = folder; this.glob = glob; } },
		Uri: { file(fsPath) { return { fsPath, toString() { return `file://${fsPath.replaceAll("\\", "/")}`; } }; } },
		Range: class { constructor(startLine, startCharacter, endLine, endCharacter) { Object.assign(this, { startLine, startCharacter, endLine, endCharacter }); } },
		Diagnostic: class { constructor(range, message, severity) { Object.assign(this, { range, message, severity }); } },
	};
	const workspaceFolder = { uri: { fsPath: root } };
	return { api: activate({ vscode, workspaceFolder, subscriptions, signal: new AbortController().signal, asAbsolutePath: relative => path.join(root, relative) }), commands, watchers, statusItems, diagnosticCalls, workspace, subscriptions, outputLines };
}

test("workspace status and command identifiers are unique per root", () => {
	const first = fixture("C:/repo/first");
	const second = fixture("C:/repo/second");
	first.api.start(() => {});
	second.api.start(() => {});
	first.api.updateDependencies({ message: "Ready", complete: true });
	assert.equal([...first.commands.keys()].some(name => name.endsWith(".runSetup")), true);
	assert.notEqual([...first.commands.keys()].find(name => name.endsWith(".check")), [...second.commands.keys()].find(name => name.endsWith(".check")));
	assert.equal(first.statusItems.length, 2);
	first.api.dispose();
	second.api.dispose();
});

test("setup inputs rerun setup while source edits rerun only checks", async () => {
	const root = "C:/repo";
	const actions = [];
	const state = fixture(root);
	state.api.start(action => actions.push(action));
	const dependenciesWatcher = state.watchers.find(watcher => watcher.pattern.glob === "dependencies/**");
	dependenciesWatcher.change({ fsPath: path.join(root, "dependencies/dependencies.lock") });
	await new Promise(resolve => setTimeout(resolve, 400));
	state.watchers.find(watcher => watcher.pattern.glob === "source/**").change({ fsPath: path.join(root, "source/a.luau") });
	await new Promise(resolve => setTimeout(resolve, 400));
	assert.deepEqual(actions, ["run", "check"]);
	state.api.dispose();
});

test("module owns one disposable and ignores editor events outside its workspace", async () => {
	const state = fixture("C:/repo");
	const actions = [];
	state.api.start(action => actions.push(action));
	assert.equal(state.subscriptions.length, 1);
	state.workspace.open({ uri: { fsPath: "C:/elsewhere/a.luau" } });
	state.workspace.change({ document: { uri: { fsPath: "C:/elsewhere/a.luau" } } });
	await new Promise(resolve => setTimeout(resolve, 400));
	assert.deepEqual(actions, []);
	state.api.dispose();
});

test("rejected controller callbacks are reported to the output channel", async () => {
	const state = fixture("C:/repo");
	state.api.start(() => Promise.reject(new Error("controller offline")));
	state.watchers.find(watcher => watcher.pattern.glob === "source/**").change({ fsPath: "C:/repo/source/a.luau" });
	await new Promise(resolve => setTimeout(resolve, 400));
	assert.ok(state.outputLines.some(line => line.includes("controller offline")));
	state.api.dispose();
});

test("setup invalidates in-flight check generations and findings in dirty documents", () => {
	const root = "C:/repo";
	const dirtyUri = { fsPath: path.join(root, "source/dirty.luau"), toString() { return `file://${this.fsPath.replaceAll("\\", "/")}`; } };
	const state = fixture(root, [{ uri: dirtyUri, isDirty: true }]);
	state.api.beginSetup(3);
	state.api.publishPreflight({ generation: 2, findings: [{ file: dirtyUri.fsPath, line: 1, column: 1, severity: "error", message: "stale" }] });
	assert.equal(state.diagnosticCalls.sets.length, 0);
	state.api.publishPreflight({ generation: 3, findings: [
		{ file: dirtyUri.fsPath, line: 1, column: 1, severity: "error", message: "disk result" },
		{ file: path.join(root, "source/clean.luau"), line: 2, column: 4, severity: "warning", message: "clean result" },
	] });
	assert.equal(state.diagnosticCalls.sets.length, 1);
	assert.equal(state.diagnosticCalls.sets[0].items[0].range.endCharacter, 4);
	state.api.dispose();
	state.api.dispose();
});

test("setup and checker status items remain independently actionable", () => {
	const state = fixture("C:/repo");
	state.api.startWatching(() => {});
	state.api.updateDependencies({ error: "network unavailable", message: "Dependency setup failed" });
	state.api.beginCheck(1);
	state.api.publishPreflight({ generation: 1, findings: [{ file: "source/a.luau", line: 1, column: 1, severity: "error", message: "bad" }] });
	const names = [...state.commands.keys()];
	assert.equal(names.filter(name => name.endsWith(".runSetup")).length, 1);
	assert.equal(names.filter(name => name.endsWith(".check")).length, 1);
	assert.equal(state.statusItems.length, 2);
	state.api.dispose();
});
