"use strict";

const fs = require("node:fs");
const path = require("node:path");

const policyFile = ".vscode/config/rules.json";
const schemaFile = ".vscode/config/rules.schema.json";
const modules = path.resolve(__dirname, "../../../build/dependencies/npm/node_modules");
const jsonTools = () => require(path.join(modules, "jsonc-parser"));
const namePattern = /^[a-z][a-z0-9]*(?:-[a-z0-9]+)*$/;
const ignored = new Set(["tests", "examples", "validation", "vendor", "generated"]);

class PolicyError extends Error {
	constructor(file, message, line = 1, column = 1) {
		super(message);
		Object.assign(this, { file, line, column });
	}
}

function readDocument(root, file) {
	const json = jsonTools();
	let text;
	try { text = fs.readFileSync(path.join(root, file), "utf8"); }
	catch (error) { throw new PolicyError(file, error.message); }
	const errors = [];
	const tree = json.parseTree(text, errors, { disallowComments: true });
	const at = (message, offset = 0) => {
		const lines = text.slice(0, offset).split(/\r\n|\r|\n/);
		return new PolicyError(file, message, lines.length, lines.at(-1).length + 1);
	};
	if (!tree || errors.length) throw at("Invalid JSON" + (errors.length ? ": " + json.printParseErrorCode(errors[0].error) : ""), errors[0]?.offset);
	function checkKeys(node) {
		if (node.type === "object") {
			const seen = new Set();
			for (const property of node.children || []) {
				const key = property.children[0];
				if (seen.has(key.value)) throw at("Duplicate key: " + key.value, key.offset);
				seen.add(key.value);
				checkKeys(property.children[1]);
			}
		} else if (node.type === "array") {
			for (const child of node.children || []) checkKeys(child);
		}
	}
	checkKeys(tree);
	return {
		value: JSON.parse(text),
		error(message, parts = []) {
			for (let end = parts.length; end >= 0; end--) {
				const node = json.findNodeAtLocation(tree, parts.slice(0, end));
				if (node) return at(message, node.offset);
			}
			return at(message);
		},
	};
}

function catalog(root) {
	const rules = new Map();
	const language = "luau";
	const start = "rules/" + language;
	const active = path.join(root, start);
	if (!fs.existsSync(active)) return rules;
	if (fs.lstatSync(path.join(root, "rules")).isSymbolicLink() || fs.lstatSync(active).isSymbolicLink()) {
		throw new PolicyError(start + "/README.md", "The active rules root must be a real directory");
	}
	function walk(directory) {
		const entries = fs.readdirSync(path.join(root, directory), { withFileTypes: true })
			.sort((left, right) => left.name.localeCompare(right.name, "en"));
		if (entries.some(entry => entry.isSymbolicLink() && ["validation.luau", "validation", "settings.json", "README.md"].includes(entry.name))) {
			throw new PolicyError(policyFile, "Rule declarations cannot be symlinks: " + directory);
		}
		const file = name => entries.some(entry => entry.name === name && entry.isFile());
		const folder = name => entries.some(entry => entry.name === name && entry.isDirectory());
		const nestedEntry = directory + "/validation/init.luau";
		if (folder("validation") && fs.existsSync(path.join(root, nestedEntry)) && fs.lstatSync(path.join(root, nestedEntry)).isSymbolicLink()) {
			throw new PolicyError(policyFile, "Rule entry cannot be a symlink: " + nestedEntry);
		}
		const single = file("validation.luau");
		const nested = folder("validation") && fs.existsSync(path.join(root, nestedEntry))
			&& fs.lstatSync(path.join(root, nestedEntry)).isFile();
		if (single || folder("validation") || folder("tests") || file("settings.json")) {
			const readme = directory + "/README.md";
			if (!file("README.md") || single === nested) {
				throw new PolicyError(file("README.md") ? readme : policyFile, directory + " needs a README.md and exactly one validator entry");
			}
			const name = path.posix.basename(directory);
			const id = language + "/" + name;
			if (directory === start || !namePattern.test(name)) throw new PolicyError(readme, "Invalid rule folder name: " + name);
			if (rules.has(id)) throw new PolicyError(readme, "Duplicate rule ID " + id + " also declared by " + rules.get(id).directory);
			const title = fs.readFileSync(path.join(root, readme), "utf8").match(/^#\s+(.+)$/m)?.[1]?.trim() || name;
			rules.set(id, {
				id, title, directory, readme, entry: single ? directory + "/validation.luau" : nestedEntry,
				schema: file("settings.json") ? directory + "/settings.json" : undefined,
			});
		}
		for (const entry of entries) {
			if (entry.isDirectory() && !ignored.has(entry.name) && !entry.name.startsWith(".")) walk(directory + "/" + entry.name);
		}
	}
	walk(start);
	return rules;
}

function workspacePath(root, input, type) {
	if (typeof input !== "string" || !input || input.includes("\0")) return;
	let value = input.replaceAll("\\", "/");
	if (value.split("/").includes("..") || /^\/\/[?.]\//.test(value)) return;
	if (process.platform === "win32") {
		value = value.replace(/^\/(?:(?:cygdrive|mnt)\/)?([a-z])(?=\/)/i, "$1:");
		if (/^\/(?!\/)/.test(value)) return;
		if (value.includes(":") && !/^[a-z]:\/[^:]*$/i.test(value)) return;
	} else if (/^[a-z]:/i.test(value)) return;
	try {
		const base = fs.realpathSync(root);
		const actual = fs.realpathSync(path.resolve(base, value));
		const relative = path.relative(base, actual);
		if (relative === ".." || relative.startsWith(".." + path.sep) || path.isAbsolute(relative)) return;
		const stat = fs.statSync(actual);
		if (type === "directory" ? !stat.isDirectory() : !stat.isFile()) return;
		return relative.split(path.sep).join("/");
	} catch { return; }
}

function resolveRule(root, rules, key) {
	if (rules.has(key)) return rules.get(key);
	const directory = workspacePath(root, key, "directory");
	if (!directory) return;
	for (const rule of rules.values()) {
		if (process.platform === "win32" ? directory.toLowerCase() === rule.directory.toLowerCase() : directory === rule.directory) return rule;
	}
}

function ajvFor(root) {
	const Ajv = require(path.join(modules, "ajv"));
	const ajv = new Ajv({ strict: true, validateFormats: true });
	ajv.addFormat("workspace-file", value => workspacePath(root, value, "file") !== undefined);
	ajv.addFormat("workspace-directory", value => workspacePath(root, value, "directory") !== undefined);
	return ajv;
}

function validationError(document, error, prefix = []) {
	const parts = error.instancePath.split("/").slice(1).map(part => part.replaceAll("~1", "/").replaceAll("~0", "~"));
	const location = [...prefix, ...parts];
	if (error.params.additionalProperty) location.push(error.params.additionalProperty);
	return document.error(location.join(" / ") + ": " + error.message, location);
}

function loadPolicy(root, rules = catalog(root)) {
	const document = readDocument(root, policyFile);
	const validate = ajvFor(root).compile(readDocument(root, schemaFile).value);
	if (!validate(document.value)) throw validationError(document, validate.errors[0]);
	const configured = new Map();
	for (const [key, value] of Object.entries(document.value.rules || {})) {
		const rule = resolveRule(root, rules, key);
		if (!rule) throw document.error("Unknown rule: " + key, ["rules", key]);
		if (configured.has(rule.id)) throw document.error("Duplicate configuration for " + rule.id, ["rules", key]);
		configured.set(rule.id, { key, value });
	}
	const defaults = { severity: "warning", fixtureSeverity: "warning", ...document.value.defaults };
	const result = new Map();
	for (const rule of rules.values()) {
		const { key = rule.id, value = {} } = configured.get(rule.id) || {};
		const scope = ["rules", key];
		let settingsCheck;
		if (rule.schema) {
			const schema = readDocument(root, rule.schema);
			try {
				if (schema.value?.type !== "object") throw new Error("Rule settings must declare an object schema");
				settingsCheck = ajvFor(root).compile(schema.value);
			} catch (error) { throw schema.error("Invalid rule settings schema: " + error.message); }
		}
		function checkSettings(settings, location) {
			if (!settingsCheck) {
				if (settings !== undefined) throw document.error(rule.id + " does not declare custom settings", location);
			} else if (!settingsCheck(settings === undefined ? {} : settings)) {
				throw validationError(document, settingsCheck.errors[0], location);
			}
		}
		checkSettings(value.settings, [...scope, "settings"]);
		for (const [index, override] of (value.overrides || []).entries()) {
			const location = [...scope, "overrides", index];
			for (const field of ["files", "excludedFiles"]) {
				for (const [item, glob] of (override[field] || []).entries()) {
					if (/^[\/]|[\\:\0]/.test(glob) || glob.split("/").some(segment => segment === ".." || segment === "")) {
						throw document.error("Expected a workspace-relative glob with forward slashes", [...location, field, item]);
					}
				}
			}
			if (Object.hasOwn(override, "settings")) checkSettings(override.settings, [...location, "settings"]);
		}
		result.set(rule.id, { ...defaults, ...value, key });
	}
	return { rules, result, document };
}

function effective(policy, file) {
	let { severity, settings } = policy;
	let settingsIndex = 0;
	const normalized = file.replaceAll("\\", "/");
	const matches = glob => path.posix.matchesGlob(normalized, glob);
	for (const [index, override] of (policy.overrides || []).entries()) {
		if (!override.files.some(matches) || override.excludedFiles?.some(matches)) continue;
		if (Object.hasOwn(override, "severity")) severity = override.severity;
		if (Object.hasOwn(override, "settings")) {
			settings = override.settings;
			settingsIndex = index + 1;
		}
	}
	return { severity, settings, settingsIndex };
}

module.exports = { catalog, effective, jsonTools, loadPolicy, policyFile, resolveRule };
