"use strict";

const assert = require("node:assert/strict");
const test = require("node:test");
const path = require("node:path");
const { registerRuleActions, headerEdit, jsonObject, diagnosticKey, findingKey, ruleQuickFix } = require("./ruleActions.cjs");

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

test("rule quick fixes are limited to direct, syntax-preserving edits", () => {
	const cases = [
		["file-system", "Declare --!strict at the top of hand-written Luau source.", "return true\n", [0, 0, 0, 0], [0, 0, "--!strict\n"]],
		["blank-lines", "Separate this statement from the preceding block with a blank line.", "if ready then\n\tRun()\nend\nreturn true\n", [3, 0, 3, 0], [source => source.indexOf("return true"), source => source.indexOf("return true"), "\n"]],
		["indentation", "Use literal tabs for code indentation.", "if ready then\n    Run()\nend\n", [1, 0, 1, 4], [source => source.indexOf("    Run"), source => source.indexOf("Run"), "\t"]],
		["todo-comments", "Describe the follow-up or remove this empty TODO.", "-- TODO\nlocal ready = true\n", [0, 0, 0, 7], [0, 8, ""]],
		["types", "Remove the repeated Luau type assertion.", "local value = (input :: string) :: string\n", [0, 31, 0, 41], [31, source => source.length - 1, ""]],
		["functions", "A bare function declaration in a returning module writes a global.", "function helper(): ()\nend\nreturn {}\n", [0, 9, 0, 15], [0, 0, "local "]],
		["strings", "Interpolation already converts this value to text. Remove the redundant tostring call.", "local text = `{tostring(name)}`\n", [0, 15, 0, 29], [15, 29, "name"]],
		["function-documentation", "Start a LuaCATS @param annotation with three dashes.", "--@param value string\n", [0, 0, 0, 21], [0, 2, "---"]],
	];
	for (const [rule, message, source, coords, expected] of cases) {
		const [line, character, endLine, endCharacter] = coords;
		const diagnostic = { message, range: { start: { line, character }, end: { line: endLine, character: endCharacter } } };
		const snapshot = { source, rule: "luau/" + rule, diagnostic };
		const fix = ruleQuickFix(snapshot, "source/example.luau");
		assert.ok(fix, rule);
		if (rule === "blank-lines" || rule === "indentation" || rule === "todo-comments" || rule === "types") {
			const [start, end, text] = expected;
			assert.deepEqual([fix.start, fix.end, fix.text], [typeof start === "function" ? start(source) : start, typeof end === "function" ? end(source) : end, text], rule);
		} else {
			assert.deepEqual([fix.start, fix.end, fix.text], expected, rule);
		}
	}
	assert.equal(ruleQuickFix({ rule: "luau/indentation", source: "  Run()\n", diagnostic: {
		message: "Use literal tabs for code indentation.", range: { start: { line: 0, character: 0 }, end: { line: 0, character: 2 } },
	} }, "source/example.luau"), undefined, "ambiguous non-four-space indentation stays manual");
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

test("non-header rule actions are preferred, candidate-checked, and applied from the current snapshot", async () => {
	const root = process.cwd();
	const source = "local MAX_COUNT = 4\nreturn MAX_COUNT\n";
	const uri = { scheme: "file", fsPath: path.join(root, "source/a.luau"), toString: () => "file:stable-const" };
	const document = {
		uri, version: 3, getText: () => source,
		positionAt(offset) { return { offset }; },
	};
	const rule = "luau/naming";
	const finding = { rule, line: 1, column: 1, endLine: 1, endColumn: 6, message: "Declare this stable Luau constant with const." };
	const range = { start: { line: 0, character: 0 }, end: { line: 0, character: 5 }, intersection: () => true };
	const readme = path.join(root, "rules/luau/style/naming/README.md");
	const diagnostic = { source: "Rules", code: { value: "naming", target: { fsPath: readme } }, message: finding.message, range };
	const key = diagnosticKey(rule, range);
	const snapshot = { source, version: 3, revision: 2, rule, diagnostic, target: findingKey(finding, source) };
	const commands = new Map();
	let provider;
	let applied;
	registerRuleActions({
		root, workflow: {}, actionSources: new Map([[uri.toString(), new Map([[key, snapshot]])]]),
		command: name => name, getRevision: () => 2,
		requestFile: async ({ source: text }) => ({ findings: text === source ? [finding] : [] }),
		vscode: {
			CodeAction: class { constructor(title, kind) { this.title = title; this.kind = kind; } },
			CodeActionKind: { QuickFix: "quickfix", RefactorExtract: "refactor.extract" },
			Range: class { constructor(start, end) { this.start = start; this.end = end; } },
			WorkspaceEdit: class { replace(_uri, rangeValue, text) { applied = { range: rangeValue, text }; } },
			workspace: { openTextDocument: async () => document, applyEdit: async () => true },
			languages: { registerCodeActionsProvider(_selector, value) { provider = value; } },
			commands: { registerCommand(name, callback) { commands.set(name, callback); } },
		},
	});
	const actions = await provider.provideCodeActions(document, range, {});
	assert.equal(actions.length, 1);
	assert.equal(actions[0].title, "Use const");
	assert.equal(actions[0].isPreferred, true);
	await commands.get(actions[0].command.command)(...actions[0].command.arguments);
	assert.equal(applied.text, "const");
	assert.equal(applied.range.start.offset, 0);
	assert.equal(applied.range.end.offset, 5);
});
