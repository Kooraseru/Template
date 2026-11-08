"use strict";

const assert = require("node:assert/strict");
const test = require("node:test");
const path = require("node:path");
const { registerRuleActions, headerEdit, jsonObject, diagnosticKey, findingKey } = require("./ruleActions.cjs");

test("header repair preserves CRLF and skips an ambiguous opening comment", () => {
	assert.deepEqual(headerEdit("--!strict\r\nreturn true\r\n", "source/a.luau"),
		{ length: 0, text: "-- source/a.luau\r\n" });
	assert.equal(headerEdit("-- explanatory comment\nreturn true", "source/a.luau"), undefined);
});

test("extraction preserves explicit string keys and nested lists and rejects ambiguous values", () => {
	const value = jsonObject('{ ["a-b"] = { "é", true, { x = -1 } }, name = "hello" }');
	assert.deepEqual(JSON.parse(JSON.stringify(value)), { "a-b": ["é", true, { x: -1 }], name: "hello" });
	for (const literal of ['{x = {},}', '{x = {1, y = 2}}', '{x = nil}', '{x = 9007199254740992}',
		'{x = 1, ["x"] = 2}', '{x = -- comment\n1}', '{x = {[2] = 1}}', '{1, 2}']) {
		assert.equal(jsonObject(literal), undefined, literal);
	}
});

test("header action requires a current finding and rejects edits that introduce another rule", async () => {
	const root = process.cwd();
	const source = "--!strict\r\nreturn true\r\n";
	const uri = { scheme: "file", fsPath: path.join(root, "source/a.luau"), toString: () => "file:a" };
	const document = { uri, version: 1, getText: () => source };
	const rule = "luau/path-headers";
	const target = { rule, line: 1, column: 1, endLine: 1, endColumn: 1, message: "Missing header" };
	const other = { ...target, rule: "luau/other", line: 2, endLine: 2, message: "Existing warning" };
	const moved = { ...other, line: 3, endLine: 3 };
	const range = { start: { line: 0, character: 0 }, end: { line: 0, character: 0 }, intersection: () => true };
	const doc = path.join(root, "rules/luau/files/path-headers/README.md");
	const diagnostic = { source: "Rules", code: { value: "path-headers", target: { fsPath: doc } }, message: target.message, range };
	const snapshots = new Map([[diagnosticKey(rule, range), { source, version: 1, revision: 0, rule, diagnostic, target: findingKey(target, source) }]]);
	let provider;
	let introducesFinding = false;
	let applied;
	const commands = new Map();
	registerRuleActions({
		root, workflow: {}, actionSources: new Map([[uri.toString(), snapshots]]), command: name => name,
		getRevision: () => 0,
		requestFile: async ({ source: text }) => ({ findings: text === source ? [target, other] :
			introducesFinding ? [moved, { ...target, rule: "luau/new" }] : [moved] }),
		vscode: {
			CodeAction: class { constructor(title) { this.title = title; } },
			CodeActionKind: { QuickFix: "quickfix" },
			Range: class {},
			WorkspaceEdit: class { replace(_uri, _range, text) { this.text = text; } },
			workspace: { openTextDocument: async () => document, applyEdit: async edit => { applied = edit.text; return true; } },
			languages: { registerCodeActionsProvider(_selector, value) { provider = value; } },
			commands: { registerCommand(name, callback) { commands.set(name, callback); } },
		},
	});
	const actions = () => provider.provideCodeActions(document, range, { diagnostics: [diagnostic] });
	const [action] = await actions();
	assert.equal(action.title, "Fix path header");
	await commands.get(action.command.command)(...action.command.arguments);
	assert.equal(applied, "-- source/a.luau\r\n");
	introducesFinding = true;
	assert.deepEqual(await actions(), []);
	introducesFinding = false;
	document.version++;
	assert.deepEqual(await actions(), []);
});
