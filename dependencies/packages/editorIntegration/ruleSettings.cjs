"use strict";

const fs = require("node:fs");
const path = require("node:path");
const { catalog, jsonTools, policyFile, resolveRule } = require("../ruleLinter/policy.cjs");

function dereference(schema, node) {
	const seen = new Set();
	while (typeof node?.$ref === "string" && node.$ref.startsWith("#/") && !seen.has(node)) {
		seen.add(node);
		node = node.$ref.slice(2).split("/").reduce((parent, segment) =>
			parent?.[segment.replaceAll("~1", "/").replaceAll("~0", "~")], schema);
	}
	return node;
}

function settingsProperties(schema, parts) {
	let node = schema;
	for (const part of parts) {
		node = dereference(schema, node);
		node = typeof part === "number" ? node?.items : node?.properties?.[part];
	}
	return dereference(schema, node)?.properties || {};
}

function initialValue(schema, shape) {
	const node = dereference(schema, shape);
	if (Object.hasOwn(node || {}, "default")) return node.default;
	if (node?.enum?.length) return node.enum[0];
	switch (node?.type) {
		case "array": return [];
		case "object": return {};
		case "boolean": return false;
		case "number": case "integer": return 0;
		case "null": return null;
		default: return "";
	}
}

function registerRuleSettings({ vscode, workspaceFolder, root }) {
	return vscode.languages.registerCompletionItemProvider({
		scheme: "file", language: "json", pattern: new vscode.RelativePattern(workspaceFolder, policyFile),
	}, {
		provideCompletionItems(document, position) {
			try {
				const json = jsonTools();
				const text = document.getText();
				const location = json.getLocation(text, document.offsetAt(position));
				const parts = location.path;
				if (parts[0] !== "rules" || !location.isAtPropertyKey) return [];
				const rules = catalog(root);
				const current = location.previousNode;
				const keyOffset = current?.type === "property" ? current.offset : undefined;
				const parent = json.findNodeAtLocation(json.parseTree(text), parts.slice(0, -1));
				const existing = new Set((parent?.children || []).map(property => property.children?.[0]?.value));
				existing.delete(parts.at(-1));
				const item = (name, detail, initial) => {
					const completion = new vscode.CompletionItem(name, vscode.CompletionItemKind.Property);
					const quoted = JSON.stringify(name);
					completion.detail = detail;
					let end = document.offsetAt(position);
					if (keyOffset !== undefined) {
						end = keyOffset + current.length;
						completion.range = new vscode.Range(document.positionAt(keyOffset), document.positionAt(end));
						if (/^\s*:/.test(text.slice(end))) {
							completion.insertText = quoted;
							return completion;
						}
					}
					completion.insertText = quoted + ": " + initial + (/^\s*"/.test(text.slice(end)) ? "," : "");
					return completion;
				};
				if (parts.length === 2) {
					const used = new Set([...existing].map(key => resolveRule(root, rules, key)?.id));
					return [...rules.values()].filter(rule => !used.has(rule.id))
						.map(rule => item(rule.id, rule.title + " - " + rule.directory, "{}"));
				}
				const rule = resolveRule(root, rules, parts[1]);
				if (!rule?.schema) return [];
				const settings = parts[2] === "settings" ? 2 : parts[2] === "overrides" && parts[4] === "settings" ? 4 : -1;
				if (settings < 0 || parts.length <= settings + 1) return [];
				const schema = JSON.parse(fs.readFileSync(path.join(root, rule.schema), "utf8"));
				return Object.entries(settingsProperties(schema, parts.slice(settings + 1, -1)))
					.filter(([name]) => !existing.has(name))
					.map(([name, shape]) => item(name, shape.description || rule.id, JSON.stringify(initialValue(schema, shape))));
			} catch {
				// The Rules run reports invalid catalog or schema files. Completion can retry after setup or an edit.
				return [];
			}
		},
	});
}

module.exports = { registerRuleSettings };
