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
	const progress = [];
	const notices = [];
	const diagnosticCalls = { sets: [], deletes: [], cleared: false };
	const workspace = {
		textDocuments,
		createFileSystemWatcher(pattern) {
			const watcher = { pattern, onDidCreate(callback) { this.create = callback; return disposable(); }, onDidChange(callback) { this.change = callback; return disposable(); }, onDidDelete(callback) { this.delete = callback; return disposable(); }, dispose() {} };
			watchers.push(watcher);
			return watcher;
		},
		onDidSaveTextDocument(callback) { this.save = callback; return disposable(); },
		onDidCloseTextDocument() { return disposable(); },
		onDidOpenTextDocument(callback) { this.open = callback; return disposable(); },
		onDidChangeTextDocument(callback) { this.change = callback; return disposable(); },
	};
	const vscode = {
		StatusBarAlignment: { Left: 1 },
		ProgressLocation: { Notification: 15 },
		DiagnosticSeverity: { Error: 0, Warning: 1, Information: 2 },
		window: {
			showInformationMessage(message, action) { return new Promise(resolve => notices.push({ message, action, resolve })); },
			withProgress(options, task) {
				const reports = [];
				const done = task({ report(update) { reports.push(update); } });
				progress.push({ options, reports, done });
				return done;
			},
			createOutputChannel() { return { appendLine(line) { outputLines.push(line); }, show() {}, dispose() {} }; },
			createStatusBarItem() { const item = { show() {}, dispose() {} }; statusItems.push(item); return item; },
		},
		languages: { registerCodeActionsProvider() { return disposable(); }, createDiagnosticCollection() { return { clear() { diagnosticCalls.cleared = true; }, set(uri, items) { diagnosticCalls.sets.push({ uri, items }); }, delete(uri) { diagnosticCalls.deletes.push(uri); }, dispose() {} }; } },
		commands: { registerCommand(name, callback) { commands.set(name, callback); return disposable(); } },
		workspace,
		RelativePattern: class { constructor(folder, glob) { this.folder = folder; this.glob = glob; } },
		Uri: { file(fsPath) { return { fsPath, toString() { return `file://${fsPath.replaceAll("\\", "/")}`; } }; } },
		Range: class { constructor(startLine, startCharacter, endLine, endCharacter) { Object.assign(this, { startLine, startCharacter, endLine, endCharacter }); } },
		Diagnostic: class { constructor(range, message, severity) { Object.assign(this, { range, message, severity }); } },
	};
	const workspaceFolder = { uri: { fsPath: root } };
	return { api: activate({ vscode, workspaceFolder, subscriptions, signal: new AbortController().signal, asAbsolutePath: relative => path.join(root, relative) }), commands, watchers, statusItems, diagnosticCalls, workspace, subscriptions, outputLines, progress, notices };
}

test("workspace status and command identifiers are unique per root", () => {
	const first = fixture("C:/repo/first");
	const second = fixture("C:/repo/second");
	first.api.start(() => {});
	second.api.start(() => {});
	first.api.updateDependencies({ message: "Ready", complete: true });
	assert.equal([...first.commands.keys()].some(name => name.endsWith(".runSetup")), true);
	assert.notEqual([...first.commands.keys()].find(name => name.endsWith(".check")), [...second.commands.keys()].find(name => name.endsWith(".check")));
	assert.equal(first.statusItems.length, 3);
	first.api.dispose();
	second.api.dispose();
});

test("only changed saves in watched paths run Preflight", async () => {
	const state = fixture("C:/repo");
	const actions = [];
	state.api.start(action => actions.push(action));
	const document = { uri: { scheme: "file", fsPath: "C:/repo/source/a.luau" }, isDirty: true };
	state.workspace.save(document);
	state.workspace.change({ document, contentChanges: [{}] });
	await new Promise(resolve => setTimeout(resolve, 400));
	assert.deepEqual(actions, []);
	state.workspace.save(document);
	await new Promise(resolve => setTimeout(resolve, 400));
	const setup = { uri: { scheme: "file", fsPath: "C:/repo/dependencies/dependencies.lock" }, isDirty: true };
	state.workspace.change({ document: setup, contentChanges: [{}] });
	state.workspace.save(setup);
	await new Promise(resolve => setTimeout(resolve, 400));
	const fixtureFile = { uri: { scheme: "file", fsPath: "C:/repo/rules/luau/tests/invalid/example.luau" }, isDirty: true };
	state.workspace.change({ document: fixtureFile, contentChanges: [{}] });
	state.workspace.save(fixtureFile);
	await new Promise(resolve => setTimeout(resolve, 400));
	assert.deepEqual(actions, ["check", "run", "rules"]);
	assert.equal(state.workspace.open, undefined);
	assert.equal(state.watchers.length, 1);
	state.api.dispose();
});

test("rejected controller callbacks are reported to the output channel", async () => {
	const state = fixture("C:/repo");
	state.api.start(() => Promise.reject(new Error("controller offline")));
	state.api.check();
	await new Promise(resolve => setImmediate(resolve));
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
	assert.equal(state.statusItems.length, 3);
	state.api.dispose();
});

test("dependency progress reports work and closes on success, failure, or disposal", async () => {
	const state = fixture("C:/repo");
	state.api.beginSetup(1);
	const first = state.progress[0];
	assert.equal(first.options.location, 15);
	state.api.updateDependencies({ message: "Loading tool", completed: 1, total: 4 });
	assert.deepEqual(first.reports, [{ message: "Loading tool 1/4", increment: 25 }]);
	state.api.updateDependencies({ message: "Ready", complete: true });
	await first.done;
	state.api.beginSetup(2);
	state.api.updateDependencies({ error: "Setup failed" });
	await state.progress[1].done;
	state.api.beginSetup(3);
	state.api.dispose();
	await state.progress[2].done;
});

test("rule changes offer one explicit Rules-only refresh", async () => {
	const state = fixture("C:/repo");
	const actions = [];
	state.api.start(action => actions.push(action));
	const watcher = state.watchers[0];
	const rule = { scheme: "file", fsPath: "C:/repo/rules/languages/luau/new/validation.luau" };
	watcher.create(rule);
	watcher.change(rule);
	watcher.delete(rule);
	await new Promise(resolve => setTimeout(resolve, 400));
	assert.deepEqual(actions, []);
	assert.equal(state.notices.length, 1);
	assert.equal(state.notices[0].action, "Refresh Rules");
	state.notices[0].resolve("Refresh Rules");
	await new Promise(resolve => setImmediate(resolve));
	assert.deepEqual(actions, ["rules"]);
	state.api.dispose();
});

test("Rules failures leave a passing compile result and its diagnostics intact", () => {
	const state = fixture("C:/repo");
	state.api.updateDependencies({ complete: true });
	state.api.beginCheck(1);
	state.api.beginRules(2);
	state.api.publishPreflight({ generation: 1, findings: [] });
	state.api.publishRules({ generation: 2, findings: [
		{ file: "source/a.luau", severity: "error", message: "Rule violation" },
		{ file: "rules/test.luau", fixture: true, severity: "warning", message: "Expected violation" },
	] });
	assert.match(state.statusItems[1].text, /Preflight passed/);
	assert.match(state.statusItems[2].text, /Rules failed/);
	assert.equal(state.diagnosticCalls.sets[1].items[0].severity, 1);
	state.api.dispose();
});
