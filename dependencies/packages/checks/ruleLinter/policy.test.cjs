"use strict";

const assert = require("node:assert/strict");
const fs = require("node:fs");
const os = require("node:os");
const path = require("node:path");
const test = require("node:test");
const { catalog, effective, loadPolicy, policyFile, resolveRule } = require("./policy.cjs");
const { registerRuleSettings } = require("../../editor/editorIntegration/ruleSettings.cjs");

function workspace(t) {
	const root = fs.mkdtempSync(path.join(os.tmpdir(), "template-rule-policy-"));
	t.after(() => fs.rmSync(root, { recursive: true, force: true }));
	const write = (file, value) => {
		const target = path.join(root, file);
		fs.mkdirSync(path.dirname(target), { recursive: true });
		fs.writeFileSync(target, typeof value === "string" ? value : JSON.stringify(value, null, 2));
	};
	write(".vscode/config/rules.schema.json", fs.readFileSync(path.resolve(__dirname, "../../../../.vscode/config/rules.schema.json"), "utf8"));
	write(policyFile, { rules: {} });
	const directory = "rules/luau/files/example";
	write(directory + "/README.md", "# Example rule");
	write(directory + "/validation.luau", "-- fixture");
	write(directory + "/settings.json", {
		type: "object", additionalProperties: false, required: ["enabled"],
		properties: { enabled: { type: "boolean" }, config: { type: "string", format: "workspace-file" } },
	});
	return { root, write, directory };
}

test("one catalog resolves native paths and keeps IDs through moves", t => {
	const { root, directory, write } = workspace(t);
	const absolute = path.join(root, directory);
	const rules = catalog(root);
	const keys = ["luau/example", directory, "./" + directory, directory.replaceAll("/", "\\"), absolute];
	if (process.platform === "win32") {
		const slash = absolute.replaceAll("\\", "/");
		for (const prefix of ["/", "/cygdrive/", "/mnt/"]) keys.push(prefix + slash[0].toLowerCase() + slash.slice(2));
	}
	for (const key of keys) assert.equal(resolveRule(root, rules, key)?.id, "luau/example", key);
	assert.equal(resolveRule(root, rules, "rules/luau/files/../files/example"), undefined);
	assert.equal(resolveRule(root, rules, os.tmpdir()), undefined);
	fs.symlinkSync(os.tmpdir(), path.join(root, "rules/luau/escape"), process.platform === "win32" ? "junction" : "dir");
	assert.equal(resolveRule(root, rules, "rules/luau/escape"), undefined);
	write(policyFile, { rules: { "luau/example": { settings: { enabled: true } }, [directory]: {} } });
	assert.throws(() => loadPolicy(root), /Duplicate configuration/);
	write(policyFile, { rules: { "luau/example": { settings: { enabled: true } } } });
	fs.renameSync(absolute, path.join(root, "rules/luau/example"));
	assert.equal(loadPolicy(root).rules.get("luau/example").directory, "rules/luau/example");
	write(directory + "/README.md", "# Duplicate");
	write(directory + "/validation.luau", "-- fixture");
	assert.throws(() => catalog(root), /Duplicate rule ID/);
});

test("validation uses the rule schema and overrides resolve independently", t => {
	const { root, write } = workspace(t);
	write("source/example.json", "{}");
	const settings = { enabled: true, config: "source\\example.json" };
	const rules = {
		"luau/example": {
			fixtureSeverity: "info", settings,
			overrides: [
				{ files: ["source/**/*.luau"], severity: "error", settings: { enabled: false } },
				{ files: ["source/**/*.luau"], excludedFiles: ["source/keep.luau"], severity: "off" },
			],
		},
	};
	write(policyFile, { rules });
	const rule = loadPolicy(root).result.get("luau/example");
	assert.equal(rule.fixtureSeverity, "info");
	assert.deepEqual(effective(rule, "source\\example.luau"), { severity: "off", settings: { enabled: false }, settingsIndex: 1 });
	assert.deepEqual(effective(rule, "source/keep.luau"), { severity: "error", settings: { enabled: false }, settingsIndex: 1 });
	assert.deepEqual(effective(rule, "ci/example.luau"), { severity: "warning", settings, settingsIndex: 0 });
	rules["luau/example"].settings.config = "source/missing.json";
	write(policyFile, { rules });
	assert.throws(() => loadPolicy(root), /workspace-file/);
	rules["luau/example"].settings = { enabled: true, typo: true };
	write(policyFile, { rules });
	assert.throws(() => loadPolicy(root), error => error.file === policyFile && error.line > 1 && /typo/.test(error.message));
	write(policyFile, '{"rules":{},"rules":{}}');
	assert.throws(() => loadPolicy(root), /Duplicate key/);
});

test("editor suggests real rule IDs and nested settings without a generated schema", t => {
	const { root, directory, write } = workspace(t);
	let provider;
	const vscode = {
		languages: { registerCompletionItemProvider(_selector, value) { provider = value; } },
		RelativePattern: class {},
		CompletionItem: class { constructor(label) { this.label = label; } },
		CompletionItemKind: { Property: 1 },
	};
	registerRuleSettings({ vscode, root });
	const complete = value => provider.provideCompletionItems(
		{ getText: () => value.replace("|", ""), offsetAt: () => value.indexOf("|") }, {},
	);
	assert.deepEqual(complete('{"rules": {|}}').map(item => item.label), ["luau/example"]);
	assert.deepEqual(complete('{"rules":{"luau/example":{"settings":{|}}}}').map(item => item.label), ["enabled", "config"]);
	write(directory + "/settings.json", {
		type: "object", properties: { nested: { $ref: "#/definitions/child" } },
		definitions: { child: { type: "object", properties: { limit: { type: "number", default: 4 } } } },
	});
	const items = complete('{"rules":{"luau/example":{"overrides":[{"settings":{"nested":{|}}}]}}}');
	assert.deepEqual(items.map(item => item.insertText), ['"limit": 4']);
});
