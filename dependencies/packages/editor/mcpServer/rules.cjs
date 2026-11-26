"use strict";
const fs = require("node:fs");
const path = require("node:path");
const { catalog } = require("../../checks/ruleLinter/policy.cjs");

function fixtureCount(directory, extension = ".luau") {
    if (!fs.existsSync(directory)) return 0;
    let count = 0;
    for (const entry of fs.readdirSync(directory, { withFileTypes: true })) {
        const child = path.join(directory, entry.name);
        if (entry.isDirectory()) count += fixtureCount(child, extension);
        else if (entry.isFile() && entry.name.endsWith(extension)) count++;
    }
    return count;
}

function listRules({ root, id } = {}) {
    if (typeof root !== "string") throw new TypeError("A workspace root is required");
    const found = [...catalog(root).values()].map(rule => ({
        // Retain the historical MCP full-path identity; expose the policy identity too.
        id: rule.directory.slice("rules/".length),
        policyId: rule.id,
        runtime: rule.runtime,
        directory: rule.directory,
        fixtures: Object.fromEntries(["valid", "invalid", "review"].map(category =>
            [category, fixtureCount(path.join(root, rule.directory, "tests", category),
                rule.runtime === "lute" ? ".luau" : ".json")])),
    })).sort((a, b) => a.id.localeCompare(b.id));
    if (id !== undefined && (typeof id !== "string" || !id.trim())) throw new TypeError("id must be a nonempty string");
    const selected = id ? found.filter(rule => rule.id === id || rule.policyId === id ||
        (!id.includes("/") && rule.id.endsWith("/" + id))) : found;
    if (id && !selected.length) throw new Error("Unknown Luau rule or product rule: " + id);
    if (selected.length > 1 && id) throw new Error("Ambiguous rule: " + id);
    return { total: found.length, selected: selected.length, rules: selected, note: "Rule discovery is not an audit or validation result." };
}
module.exports = { listRules, fixtureCount };
