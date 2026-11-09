"use strict";

const assert = require("node:assert/strict");
const path = require("node:path");
const test = require("node:test");
const { activate } = require("./activate.cjs");
const workflow = require("../../../.vscode/config/workflow.json");

function disposable() { return { dispose() {} }; }
function fixture(root, textDocuments = [], autoRefresh = workflow.rules.autoRefresh) {
	const commands = new Map();
	const watchers = [];
	const statusItems = [];
	const outputLines = [];
	const subscriptions = [];
	const progress = [];
	const notices = [];
	const diagnosticCalls = { sets: [], deletes: [], cleared: false };
	const native = [];
	const workspace = {
		textDocuments,
		createFileSystemWatcher(pattern) {
			const watcher = { pattern, onDidCreate(callback) { this.create = callback; return disposable(); }, onDidChange(callback) { this.change = callback; return disposable(); }, onDidDelete(callback) { this.delete = callback; return disposable(); }, dispose() {} };
			watchers.push(watcher);
			return watcher;
		},
		onDidSaveTextDocument(callback) { this.save = callback; return disposable(); },
		onDidCloseTextDocument(callback) { this.close = callback; return disposable(); },
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
		languages: { registerCompletionItemProvider() { return disposable(); }, registerCodeActionsProvider() { return disposable(); }, createDiagnosticCollection() { return { clear() { diagnosticCalls.cleared = true; }, set(uri, items) { diagnosticCalls.sets.push({ uri, items }); }, delete(uri) { diagnosticCalls.deletes.push(uri); }, dispose() {} }; } },
		commands: { registerCommand(name, callback) { commands.set(name, callback); return disposable(); } },
		workspace,
		RelativePattern: class { constructor(folder, glob) { this.folder = folder; this.glob = glob; } },
		Uri: { file(fsPath) { return { fsPath, toString() { return `file://${fsPath.replaceAll("\\", "/")}`; } }; } },
		Range: class { constructor(startLine, startCharacter, endLine, endCharacter) { Object.assign(this, { startLine, startCharacter, endLine, endCharacter }); } },
		Diagnostic: class { constructor(range, message, severity) { Object.assign(this, { range, message, severity }); } },
	};
	const workspaceFolder = { uri: { fsPath: root } };
	vscode.languages.getDiagnostics = () => native;
	vscode.languages.onDidChangeDiagnostics = callback => {
		diagnosticCalls.change = callback;
		return disposable();
	};
	const config = { ...workflow, rules: { ...workflow.rules, autoRefresh } };
	return { api: activate({ vscode, workspaceFolder, subscriptions, signal: new AbortController().signal, asAbsolutePath: relative => path.join(root, relative) }, config), commands, watchers, statusItems, diagnosticCalls, workspace, subscriptions, outputLines, progress, notices, native };
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

const fileUri = fsPath => ({ scheme: "file", fsPath, toString: () => "file://" + fsPath.replaceAll("\\", "/") });
const waitForFileCheck = () => new Promise(resolve => setTimeout(resolve, 400));

test("unsaved edits and undo check the current buffer silently, and save reuses its result", async () => {
	const document = { uri: fileUri("C:/repo/source/a.luau"), version: 1, isDirty: true, text: "return true", getText() { return this.text; } };
	const state = fixture("C:/repo", [document]);
	const actions = [];
	state.api.start((action, payload) => {
		actions.push(action === "file" ? JSON.parse(payload) : action);
		return { scope: "file", findings: [] };
	});
	state.workspace.save(document);
	state.workspace.change({ document, contentChanges: [{}] });
	document.version++;
	document.text = "return false";
	state.workspace.change({ document, contentChanges: [{}] });
	await waitForFileCheck();
	assert.deepEqual(actions.map(action => action.source), ["return false"]);
	document.version++;
	document.text = "return true";
	state.workspace.change({ document, contentChanges: [{}] });
	await waitForFileCheck();
	assert.deepEqual(actions.map(action => action.source), ["return false", "return true"]);
	document.isDirty = false;
	state.workspace.save(document);
	state.watchers[0].change(document.uri);
	await waitForFileCheck();
	assert.equal(actions.length, 2);
	assert.equal(state.progress.length, 0);
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
	assert.equal(state.statusItems.length, 2);
	state.api.dispose();
});

test("clicking provider status requests a provider reload", async () => {
	const state = fixture("C:/repo");
	const actions = [];
	state.api.start(action => actions.push(action));
	state.api.updateDependencies({ complete: true });
	assert.match(state.statusItems[0].text, /Providers ready/);
	await state.commands.get(state.statusItems[0].command)();
	assert.deepEqual(actions, ["reloadProviders"]);
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
	const state = fixture("C:/repo", [], false);
	const actions = [];
	state.api.start(action => actions.push(action));
	const watcher = state.watchers[0];
	const rule = { scheme: "file", fsPath: "C:/repo/rules/luau/style/new/README.md" };
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

test("automatic Rules refresh combines saves and disk events without prompting", async () => {
	const state = fixture("C:/repo", [], true);
	const actions = [];
	state.api.start((action, payload) => actions.push(action === "file" ? JSON.parse(payload) : action));
	const watcher = state.watchers[0];
	const rule = { scheme: "file", fsPath: "C:/repo/rules/luau/style/new/validation.luau" };
	rule.fsPath = "C:/repo/rules/luau/style/new/validation.luau";
	const document = { uri: rule, isDirty: true, getText: () => "return true" };
	state.workspace.change({ document, contentChanges: [{}] });
	await new Promise(resolve => setTimeout(resolve, 400));
	assert.equal(actions.length, 1);
	assert.equal(actions[0].scope, "file");
	actions.length = 0;
	state.workspace.save(document);
	watcher.change(rule);
	watcher.change({ scheme: "file", fsPath: "C:/repo/.vscode/config/rules.json" });
	watcher.create(rule);
	watcher.delete(rule);
	await new Promise(resolve => setTimeout(resolve, 400));
	assert.deepEqual(actions, ["rules"]);
	assert.deepEqual(state.notices, []);
	state.api.dispose();
});

test("checker changes refresh Rules and edits in a nested build source are checked", async () => {
	const file = ".github/ci/components/governance/branches/build/branchBuilder.luau";
	const document = { uri: fileUri("C:/repo/" + file), version: 1, isDirty: true, getText: () => "return true" };
	const state = fixture("C:/repo", [document], true);
	const actions = [];
	state.api.start((action, payload) => {
		actions.push(action === "file" ? JSON.parse(payload) : action);
		return { scope: "file", findings: [] };
	});
	state.workspace.change({ document, contentChanges: [{}] });
	await waitForFileCheck();
	assert.equal(actions[0].file, file);
	actions.length = 0;
	state.watchers[0].change(fileUri("C:/repo/dependencies/packages/preflightChecker/index.ts"));
	await new Promise(resolve => setTimeout(resolve, 850));
	assert.ok(actions.includes("rules"));
	assert.ok(actions.some(action => action.file === file));
	state.api.dispose();
});

test("a workspace Rules run refreshes dirty buffers after provider setup", async () => {
	const file = ".github/ci/components/governance/branches/build/branchBuilder.luau";
	const document = { uri: fileUri("C:/repo/" + file), version: 1, isDirty: true, getText: () => "return true" };
	const state = fixture("C:/repo", [document]);
	const actions = [];
	state.api.start((action, payload) => {
		actions.push(action === "file" ? JSON.parse(payload) : action);
		return { scope: "file", findings: [] };
	});
	state.api.beginSetup({ generation: 1 });
	state.api.updateDependencies({ complete: true });
	state.api.beginRules({ generation: 2, trigger: "manual" });
	await waitForFileCheck();
	assert.ok(actions.some(action => action.file === file));
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
	assert.match(state.statusItems[1].text, /CI Preflight passed/);
	assert.equal(state.statusItems[1].tooltip, "CI compile and Bootstrap plan checks passed. Click to rerun.");
	assert.equal(state.statusItems.length, 2);
	assert.equal(state.diagnosticCalls.sets[1].items[0].severity, 1);
	state.api.dispose();
});

test("editor tool diagnostics are published without changing Preflight status", () => {
	const state = fixture("C:/repo");
	state.api.updateDependencies({ complete: true });
	state.api.publishPreflight({ findings: [
		{ file: "source/unopened.luau", source: "Luau LSP workspace", editorTool: true, severity: "error", message: "Type mismatch" },
	] });
	assert.match(state.statusItems[1].text, /Preflight passed/);
	assert.deepEqual(state.diagnosticCalls.sets[0].items.map(item => item.source), ["Luau LSP workspace"]);
	state.api.dispose();
});

test("native Luau replaces matching workspace findings and closing restores coverage", () => {
	const state = fixture("C:/repo");
	state.api.start(() => {});
	const file = "source/unopened.luau";
	const finding = { file, line: 5, column: 24, severity: "error", message: "Unknown type 'External.any'" };
	state.api.publishPreflight({ findings: [
		{ ...finding, source: "Lute" },
		{ ...finding, source: "Luau LSP workspace", editorTool: true },
		{ ...finding, source: "TypeScript", severity: "warning", message: "Formatting differs" },
	] });
	const { uri, items } = state.diagnosticCalls.sets.at(-1);
	assert.deepEqual(items.map(item => item.source), ["Luau LSP workspace", "TypeScript"]);
	state.native.push({ ...items[0], source: "Luau", message: "TypeError: " + finding.message });
	state.diagnosticCalls.change({ uris: [uri] });
	assert.deepEqual(state.diagnosticCalls.sets.at(-1).items.map(item => item.source), ["TypeScript"]);
	const updates = state.diagnosticCalls.sets.length;
	state.diagnosticCalls.change({ uris: [uri] });
	assert.equal(state.diagnosticCalls.sets.length, updates);
	state.native.pop();
	state.diagnosticCalls.change({ uris: [uri] });
	assert.deepEqual(state.diagnosticCalls.sets.at(-1).items.map(item => item.source), ["Luau LSP workspace", "TypeScript"]);
	state.api.dispose();
});

test("missing files and ignored paths are skipped while fixture saves are scoped", async () => {
	const state = fixture("C:/repo");
	const actions = [];
	state.api.start((action, payload) => { actions.push(action === "file" ? JSON.parse(payload) : action); });
	const uri = file => fileUri("C:/repo/" + file);
	state.watchers[0].change(uri("source/unopened.luau"));
	state.watchers[0].delete(uri("source/removed.luau"));
	await waitForFileCheck();
	assert.deepEqual(actions.map(action => [action.scope, action.file, action.fixture]), []);
	state.watchers[0].change(uri("dependencies/node_modules/example/ignored.luau"));
	state.watchers[0].change(uri("rules/luau/style/new/tests/invalid/fixture.luau"));
	await waitForFileCheck();
	assert.deepEqual(actions.map(action => [action.scope, action.file, action.fixture]),
		[["file", "rules/luau/style/new/tests/invalid/fixture.luau", true]]);
	assert.equal(state.progress.length, 0);
	state.api.dispose();
});
test("startup and manual compile show progress while automatic compile uses the status bar", () => {
	const state = fixture("C:/repo");
	state.api.updateDependencies({ complete: true });
	state.api.beginCheck({ generation: 1, trigger: "startup" });
	assert.equal(state.progress.length, 1);
	state.api.publishPreflight({ generation: 1, findings: [] });
	for (let generation = 2; generation <= 5; generation++) {
		state.api.beginCheck({ generation, trigger: "automatic" });
		assert.equal(state.progress.length, 1);
		assert.match(state.statusItems[1].text, /CI Preflight running/);
		state.api.publishPreflight({ generation, findings: [] });
	}
	assert.match(state.statusItems[1].text, /CI Preflight passed/);
	state.api.beginCheck({ generation: 6, trigger: "manual" });
	assert.equal(state.progress.length, 2);
	state.api.dispose();
});

test("checks with an omitted trigger stay quiet", () => {
	const state = fixture("C:/repo");
	state.api.updateDependencies({ complete: true });
	state.api.beginCheck({ generation: 1 });
	state.api.beginRules({ generation: 2 });
	state.api.beginSetup({ generation: 3 });
	assert.equal(state.progress.length, 0);
	state.api.dispose();
});
