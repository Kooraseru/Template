import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import { spawnSync } from "node:child_process";
import { fileURLToPath } from "node:url";
import { effective, loadPolicy, policyFile } from "../ruleLinter/policy.cjs";

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "../../..");
const ignoredDirectories = new Set([".git", ".codex", "build", "node_modules", "vendor", "rules-old"]);
const configuration = ".vscode/config/typescript/tsconfig.json";
const lute = path.join(root, "build/dependencies/bin/lute", process.platform === "win32" ? "lute.exe" : "lute");
const typescript = path.join(root, "build/dependencies/npm/node_modules/typescript/bin/tsc");

function finding(file: string, line: number, column: number, severity: string, source: string, message: string): void {
	console.log(`${path.resolve(root, file)}:${line}:${column}: ${severity}: [${source}] ${message}`);
}

function luauSources(directory = root, includeFixtures = false): string[] {
	const result: string[] = [];
	for (const entry of fs.readdirSync(directory, { withFileTypes: true })) {
		if (entry.isSymbolicLink()) continue;
		const file = path.join(directory, entry.name);
		const fixtureDirectory = ["valid", "invalid", "review", "examples"].includes(entry.name) && path.relative(root, file).startsWith("rules" + path.sep + "luau" + path.sep);
		if (entry.isDirectory() && !ignoredDirectories.has(entry.name) && (includeFixtures || !fixtureDirectory)) result.push(...luauSources(file, includeFixtures));
		else if (entry.isFile() && entry.name.endsWith(".luau")) result.push(path.relative(root, file));
	}
	return result.sort();
}

async function dependenciesReady(): Promise<boolean> {
	const required = [
		lute,
		typescript,
		path.join(root, ".luaurc"),
		path.join(root, "build/dependencies/.loader-state.json"),
		path.join(root, "build/dependencies/npm/node_modules/@types/node/index.d.ts"),
	];
	const deadline = Date.now() + 120000;
	while (required.some(file => !fs.existsSync(file))) {
		if (Date.now() > deadline) return false;
		await new Promise(resolve => setTimeout(resolve, 200));
	}
	return true;
}

type Diagnostic = { file: string; line: number; column: number; severity: string; source: string; message: string };

function compilerDiagnostics(output: string, source: string): Diagnostic[] {
	const diagnostics: Diagnostic[] = [];
	for (const line of output.split(/\r?\n/)) {
		const match = source === "TypeScript"
			? line.match(/^(.*?)\((\d+),(\d+)\): (error|warning) TS\d+: (.*)$/)
			: line.match(/^(.*?):(\d+):(\d+)(?:-\d+(?::\d+)?)?: \(W\d+\) (?:TypeError|SyntaxError): (.*)$/);
		if (match) diagnostics.push({ file: match[1], line: Number(match[2]), column: Number(match[3]), severity: source === "TypeScript" ? match[4] : "error", source, message: source === "TypeScript" ? match[5] : match[4] });
	}
	return diagnostics;
}

function lintDiagnostics(output: string): Diagnostic[] {
	const diagnostics: Diagnostic[] = [];
	let heading: { severity: string; source: string; message: string } | undefined;
	for (const line of output.split(/\r?\n/)) {
		const start = line.match(/^(error|warning|info)\[([^\]]+)\]: (.*)$/);
		if (start) heading = { severity: start[1] === "info" ? "information" : start[1], source: `Lute lint: ${start[2]}`, message: start[3] };
		const location = line.match(/┌── (.*):(\d+):(\d+)(?:-\d+(?::\d+)?)? ──/);
		if (heading && location) {
			diagnostics.push({ ...heading, file: location[1], line: Number(location[2]), column: Number(location[3]) });
			heading = undefined;
		}
		if (line.startsWith("Error applying lint rule")) diagnostics.push({ file: configuration, line: 1, column: 1, severity: "error", source: "Lute lint", message: line });
	}
	return diagnostics;
}

function check(program: string, args: string[], source: string): void {
	console.log(`::preflight-stage::${source}`);
	const result = spawnSync(program, args, { cwd: root, encoding: "utf8", windowsHide: true, timeout: 30000, maxBuffer: 16 * 1024 * 1024, env: { ...process.env, ELECTRON_RUN_AS_NODE: "1" } });
	const output = `${result.stdout || ""}\n${result.stderr || ""}`;
	const diagnostics = source === "Lute lint" ? lintDiagnostics(output) : compilerDiagnostics(output, source);
	for (const item of diagnostics) finding(item.file, item.line, item.column, item.severity, item.source, item.message);
	if (result.error || (result.status !== 0 && diagnostics.length === 0)) {
		finding(configuration, 1, 1, "error", source, result.error?.message || output.trim().replace(/\s+/g, " ") || `Checker exited with status ${result.status}`);
	}
}

function checkCiPlans(): void {
	const cli = path.join(root, "build/dependencies/npm/node_modules/preflight/bin/preflight.js");
	const provider = ".github/ci/preflight/provider.cjs";
	for (const entry of ["pull_request", "push", "workflow_dispatch"]) {
		const source = "Bootstrap plan (" + entry + ")";
		console.log("::preflight-stage::" + source);
		const result = spawnSync(process.execPath, [cli, "plan", "--provider", provider, "--entry", entry, "--json"], {
			cwd: root, encoding: "utf8", windowsHide: true, timeout: 30000,
		});
		let report;
		try { report = JSON.parse(result.stdout || ""); } catch { /* Report process failures below. */ }
		const diagnostics: Array<{ path?: string; line?: number; column?: number; severity: string; message: string }> = report?.diagnostics || [];
		for (const item of diagnostics) {
			finding(item.path && fs.existsSync(path.resolve(root, item.path)) ? item.path : provider,
				item.line || 1, item.column || 1, item.severity, source, item.message);
		}
		if ((result.error || result.status !== 0 || report?.status !== "passed") && !diagnostics.some(item => item.severity === "error")) {
			finding(provider, 1, 1, "error", source,
				(result.error?.message || result.stderr?.trim() || "Preflight did not return a passing plan.").replace(/\s+/g, " "));
		}
	}
}

function editorLuauChecks(): void {
	const analyzer = process.env.TEMPLATE_LUAU_ANALYZER;
	const toolConfig = ".vscode/settings.json";

	function run(program: string, args: string[], source: string) {
		console.log("::preflight-stage::" + source);
		return spawnSync(program, args, { cwd: root, encoding: "utf8", windowsHide: true, timeout: 30000, maxBuffer: 16 * 1024 * 1024 });
	}

	if (analyzer) {
		const source = "Luau LSP workspace";
		const inputs = luauSources(root, true);
		const fileKey = (file: string) => {
			const absolute = path.resolve(root, file);
			return process.platform === "win32" ? absolute.toLowerCase() : absolute;
		};
		const inputKeys = new Set(inputs.map(fileKey));
		if (!inputs.length) return;
		const configured = process.env.TEMPLATE_LUAU_SETTINGS;
		const baseConfig = process.env.TEMPLATE_LUAU_BASE_CONFIG;
		const sourcemap = process.env.TEMPLATE_LUAU_SOURCEMAP;
		const settingsDir = configured ? fs.mkdtempSync(path.join(os.tmpdir(), "template-luau-")) : undefined;
		const args = ["analyze", "--formatter=gnu"];
		let result;
		try {
			if (settingsDir) {
				const settingsFile = path.join(settingsDir, "settings.json");
				fs.writeFileSync(settingsFile, configured!);
				args.push("--settings", settingsFile);
				if (JSON.parse(configured!)["luau-lsp.fflags.enableByDefault"] === false) args.push("--no-flags-enabled");
			} else args.push("--platform=standard", "--flag=LuauSolverV2=true");
			if (baseConfig) args.push("--base-luaurc", baseConfig);
			if (sourcemap) args.push("--sourcemap", sourcemap);
			result = run(analyzer, [...args, ...inputs], source);
		} finally {
			if (settingsDir) fs.rmSync(settingsDir, { recursive: true, force: true });
		}
		const seen = new Set<string>();
		let reported = false;
		for (const line of [result.stdout, result.stderr].join("\n").split(/\r?\n/)) {
			const match = line.match(/^(.*):(\d+)\.(\d+)(?:-\d+\.\d+)?: ([^:]+): (.*)$/);
			if (!match) continue;
			const [, file, row, column, category, message] = match;
			reported = true;
			if (!inputKeys.has(fileKey(file)) || seen.has(line)) continue;
			seen.add(line);
			finding(file, Number(row), Number(column), /^(TypeError|SyntaxError)$/.test(category) ? "error" : "warning", source, message);
		}
		if (result.error || (result.status !== 0 && !reported)) {
			finding(toolConfig, 1, 1, "error", source, result.error?.message || "Workspace analysis failed.");
		}
	}

}

function reportRuleError(error: unknown): void {
	const detail = error as Partial<Diagnostic>;
	finding(detail.file || policyFile, detail.line || 1, detail.column || 1, "error", "Rules",
		error instanceof Error ? error.message : String(error));
	process.exitCode = 1;
}

function checkRepositoryRules(sources: string[]): void {
	console.log("::preflight-stage::Repository rules");
	let policy;
	try { policy = loadPolicy(root); }
	catch (error) { reportRuleError(error); return; }
	const paths = sources.map(file => file.split(path.sep).join("/"));
	const entries = [...policy.rules.values()].map(rule => {
		const configured = policy.result.get(rule.id);
		const variants = [];
		const settingsFor: Record<string, number> = Object.create(null);
		for (const [index, override] of (configured.overrides || []).entries()) {
			if (Object.hasOwn(override, "settings")) variants.push({ index: index + 1, settings: override.settings });
		}
		if (variants.length) for (const file of paths) {
			const { settingsIndex } = effective(configured, file);
			if (settingsIndex) settingsFor[file] = settingsIndex;
		}
		const settings = configured.settings ?? (rule.schema ? {} : undefined);
		return { ...rule, configurable: Boolean(rule.schema), settings, variants, settingsFor };
	});
	const result = spawnSync(lute, ["run", "dependencies/packages/ruleLinter/editor.luau"], {
		cwd: root, encoding: "utf8", windowsHide: true, timeout: 30000, maxBuffer: 16 * 1024 * 1024,
		input: JSON.stringify({ sources: paths, entries }) + "\n",
	});
	if (result.error || result.status !== 0) {
		const detail = result.error?.message || result.stderr?.trim().replace(/\s+/g, " ") || "Lute exited with status " + result.status;
		finding("dependencies/packages/ruleLinter/editor.luau", 1, 1, "error", "Repository rules", "Checker failed: " + detail);
		process.exitCode = 1;
		return;
	}
	const marker = "::rule-finding::";
	const settingsError = "::rule-settings-error::";
	for (const line of (result.stdout || "").split(/\r?\n/)) {
		if (!line) continue;
		if (line.startsWith(settingsError)) {
			const failure = JSON.parse(line.slice(settingsError.length));
			const scope = ["rules", policy.result.get(failure.rule).key];
			if (failure.index) scope.push("overrides", failure.index - 1);
			reportRuleError(policy.document.error(failure.rule + ": " + failure.message, [...scope, "settings"]));
			continue;
		}
		if (line.startsWith(marker)) {
			const rule = JSON.parse(line.slice(marker.length));
			const configured = policy.result.get(rule.rule);
			const severity = rule.fixtureFailure || rule.checkerFailure ? "error" : rule.fixture ? configured.fixtureSeverity
				: effective(configured, rule.file).severity;
			if (severity === "error" && !rule.fixture) process.exitCode = 1;
			if (severity !== "off") console.log(marker + JSON.stringify({ ...rule, severity: severity === "info" ? "information" : severity }));
			continue;
		}
		console.log(line);
	}
}

if (await dependenciesReady()) {
	const sources = luauSources();
	if (process.argv.includes("--rules")) {
		if (sources.length) check(lute, ["lint", ...sources], "Lute lint");
		const ruleSources = sources.filter(file => {
			const relative = file.split(path.sep).join("/");
			const directories = relative.split("/").slice(0, -1);
			const activeValidatorSource = relative.startsWith("rules/luau/") && !directories.includes("tests");
			return (activeValidatorSource || ["source/", ".github/ci/", "dependencies/packages/"].some(prefix => relative.startsWith(prefix)))
				&& !directories.some(segment => ["generated", "vendor", "examples"].includes(segment));
		});
		checkRepositoryRules(ruleSources);
	} else {
		check(process.execPath, [typescript, "--project", configuration, "--pretty", "false"], "TypeScript");
		if (sources.length) check(lute, ["check", ...sources], "Lute");
		if (process.argv.includes("--ci")) checkCiPlans();
		editorLuauChecks();
	}
} else {
	finding("dependencies/dependencies.json", 1, 1, "error", "Preflight", "Dependencies are unavailable. Run workspace dependency setup and check its status-bar output.");
}
