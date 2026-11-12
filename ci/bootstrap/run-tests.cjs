"use strict";
const fs = require("node:fs");
const path = require("node:path");
const { spawnSync } = require("node:child_process");

const ROOT = path.resolve(__dirname, "../..");
const FILE = /\.test\.(?:cjs|ts)$/;
const IGNORED = new Set(["node_modules", "managed", ".git", ".workspace", "build"]);

function walk(directory, root = ROOT, found = []) {
	if (!fs.existsSync(directory)) return found;
	for (const entry of fs.readdirSync(directory, { withFileTypes: true })) {
		const file = path.join(directory, entry.name);
		if (entry.isSymbolicLink()) throw new Error("Tests cannot follow symlinks: " + file);
		if (entry.isDirectory()) {
			if (!IGNORED.has(entry.name)) walk(file, root, found);
		} else if (entry.isFile()) {
			found.push(path.relative(root, file).split(path.sep).join("/"));
		}
	}
	return found;
}

function discover(root = ROOT) {
	const universal = [
		...walk(path.join(root, "ci"), root),
		...walk(path.join(root, "dependencies/packages"), root),
		...walk(path.join(root, "tests/universal"), root),
	].filter(file => FILE.test(file)).sort();
	if (universal.length === 0) throw new Error("No universal Template tests were found");
	const files = walk(path.join(root, "tests/features"), root);
	const suiteFiles = files.filter(file => file.endsWith("/suite.json")).sort();
	const suites = suiteFiles.map(file => {
		const spec = JSON.parse(fs.readFileSync(path.join(root, file), "utf8"));
		const directory = path.posix.dirname(file);
		if (!spec || spec.version !== 1 || !Array.isArray(spec.command) || spec.command.length === 0 ||
			spec.command.some(arg => typeof arg !== "string" || arg.length === 0 || /[\r\n\0]/.test(arg)) ||
			!Number.isSafeInteger(spec.timeoutSeconds) || spec.timeoutSeconds < 1 || spec.timeoutSeconds > 3600) {
			throw new Error("Invalid feature test suite: " + file);
		}
		return { file, directory, command: spec.command, timeoutSeconds: spec.timeoutSeconds };
	});
	const feature = files.filter(file => FILE.test(file) &&
		!suites.some(suite => file.startsWith(suite.directory + "/"))).sort();
	return { universal, feature, suites };
}

function execute(label, command, timeoutSeconds, root = ROOT) {
	console.log("::group::" + label);
	const result = spawnSync(command[0], command.slice(1), {
		cwd: root, stdio: "inherit", timeout: timeoutSeconds * 1000, shell: false,
		env: process.env,
	});
	console.log("::endgroup::");
	if (result.error || result.status !== 0) {
		throw new Error(label + " failed: " + (result.error?.message || "exit " + result.status));
	}
}

function run(root = ROOT) {
	const { universal, feature, suites } = discover(root);
	execute("Universal Template tests (" + universal.length + " files)", [process.execPath, "--test", ...universal], 1200, root);
	if (feature.length) execute("Feature tests (" + feature.length + " files)", [process.execPath, "--test", ...feature], 1200, root);
	for (const suite of suites) execute("Feature suite: " + suite.directory, suite.command, suite.timeoutSeconds, root);
	console.log("::notice::All universal and feature test suites passed");
	return { universal: universal.length, feature: feature.length, customSuites: suites.length };
}

module.exports = { walk, discover, execute, run };
if (require.main === module) {
	try { run(); } catch (error) {
		console.error("::error::" + (error instanceof Error ? error.message : String(error)));
		process.exitCode = 1;
	}
}
