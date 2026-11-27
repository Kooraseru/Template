"use strict";

const fs = require("node:fs");
const path = require("node:path");

function fixtureCount(directory) {
	if (!fs.existsSync(directory)) return 0;
	let count = 0;
	for (const entry of fs.readdirSync(directory, { withFileTypes: true })) {
		const child = path.join(directory, entry.name);
		if (entry.isDirectory()) count += fixtureCount(child);
		else if (entry.isFile() && entry.name.endsWith(".luau")) count++;
	}
	return count;
}

function discover(root, directory, found) {
	for (const entry of fs.readdirSync(directory, { withFileTypes: true })) {
		if (!entry.isDirectory() || ["tests", "examples", "validation"].includes(entry.name)) continue;
		const child = path.join(directory, entry.name);
		const single = fs.existsSync(path.join(child, "validation.luau"));
		const module = fs.existsSync(path.join(child, "validation", "init.luau"));
		if (single && module) throw new Error(`Ambiguous Luau validators in ${path.relative(root, child)}`);
		if (single || module) {
			found.push({
				id: "luau/" + path.relative(path.join(root, "rules/luau"), child).split(path.sep).join("/"),
				directory: path.relative(root, child).split(path.sep).join("/"),
				fixtures: Object.fromEntries(["valid", "invalid", "review"].map(category =>
					[category, fixtureCount(path.join(child, "tests", category))])),
			});
		} else discover(root, child, found);
	}
}

function listRules({ root, id } = {}) {
	if (typeof root !== "string") throw new TypeError("A workspace root is required");
	const directory = path.join(root, "rules/luau");
	const found = [];
	discover(root, directory, found);
	found.sort((a, b) => a.id.localeCompare(b.id));
	if (new Set(found.map(rule => rule.id)).size !== found.length) throw new Error("Duplicate Luau rule identity");
	if (id !== undefined && (typeof id !== "string" || !id.trim())) throw new TypeError("id must be a nonempty string");
	let selected = found;
	if (id) {
		selected = found.filter(rule => rule.id === id || !id.includes("/") && rule.id.endsWith("/" + id));
		if (!selected.length) throw new Error(`Unknown Luau rule: ${id}`);
		if (selected.length > 1) throw new Error(`Ambiguous Luau rule: ${id}. Use a full rule ID.`);
	}
	return { total: found.length, selected: selected.length, rules: selected, note: "Rule discovery is not an audit or validation result." };
}

module.exports = { listRules, fixtureCount };
