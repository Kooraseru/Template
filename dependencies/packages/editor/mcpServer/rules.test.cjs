"use strict";

const test = require("node:test");
const assert = require("node:assert/strict");
const fs = require("node:fs");
const os = require("node:os");
const path = require("node:path");
const { listRules } = require("./rules.cjs");

const root = path.resolve(__dirname, "../../../..");

test("Discovers repository rules with full identities and actual fixture files", () => {
	const inventory = listRules({ root });
	assert.ok(inventory.total > 0);
	assert.ok(inventory.rules.some(rule => rule.id === "luau/design/declarative-data"));
	const rule = listRules({ root, id: "declarative-data" });
	assert.equal(rule.selected, 1);
	assert.equal(rule.rules[0].fixtures.invalid, 10);
	assert.match(rule.note, /not an audit/);
	assert.throws(() => listRules({ root, id: "nonexistent" }), /Unknown Luau rule/);
});

test("Nested fixture directories count Luau cases, not directories", () => {
	const directory = fs.mkdtempSync(path.join(os.tmpdir(), "template-mcp-rules-"));
	try {
		const rule = path.join(directory, "rules/luau/design/example");
		fs.mkdirSync(path.join(rule, "tests/valid/nested"), { recursive: true });
		fs.writeFileSync(path.join(rule, "validation.luau"), "return {}");
		fs.writeFileSync(path.join(rule, "tests/valid/nested/example.luau"), "return true");
		fs.writeFileSync(path.join(rule, "tests/valid/README.md"), "not a case");
		const inventory = listRules({ root: directory });
		assert.equal(inventory.rules[0].fixtures.valid, 1);
		fs.mkdirSync(path.join(rule, "validation"));
		fs.writeFileSync(path.join(rule, "validation/init.luau"), "return {}");
		assert.throws(() => listRules({ root: directory }), /Ambiguous Luau validators/);
	} finally {
		fs.rmSync(directory, { recursive: true, force: true });
	}
});
