import fs from "node:fs";
import path from "node:path";
import { spawnSync } from "node:child_process";
import { fileURLToPath } from "node:url";

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "../../..");
const ignoredDirectories = new Set([".git", ".codex", "build", "node_modules", "vendor"]);
const configuration = ".vscode/config/typescript/tsconfig.json";
const lute = path.join(root, "build/dependencies/binaries/lute", process.platform === "win32" ? "lute.exe" : "lute");
const typescript = path.join(root, "build/dependencies/packages/typescript/bin/tsc");

function finding(file: string, line: number, column: number, severity: string, source: string, message: string): void {
	console.log(`${path.resolve(root, file)}:${line}:${column}: ${severity}: [${source}] ${message}`);
}

function luauSources(directory = root): string[] {
	const result: string[] = [];
	for (const entry of fs.readdirSync(directory, { withFileTypes: true })) {
		if (entry.isSymbolicLink()) continue;
		const file = path.join(directory, entry.name);
		if (entry.isDirectory() && !ignoredDirectories.has(entry.name)) result.push(...luauSources(file));
		else if (entry.isFile() && entry.name.endsWith(".luau")) result.push(path.relative(root, file));
	}
	return result.sort();
}

async function dependenciesReady(): Promise<boolean> {
	const required = [
		lute,
		typescript,
		path.join(root, ".luaurc"),
		path.join(root, "build/dependencies/packages/lute/.dependency.json"),
		path.join(root, "build/dependencies/packages/typescript/.dependency.json"),
		path.join(root, "build/dependencies/types/node/.dependency.json"),
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
	const result = spawnSync(program, args, { cwd: root, encoding: "utf8", windowsHide: true, timeout: 30000, maxBuffer: 16 * 1024 * 1024, env: { ...process.env, ELECTRON_RUN_AS_NODE: "1" } });
	const output = `${result.stdout || ""}\n${result.stderr || ""}`;
	const diagnostics = source === "Lute lint" ? lintDiagnostics(output) : compilerDiagnostics(output, source);
	for (const item of diagnostics) finding(item.file, item.line, item.column, item.severity, item.source, item.message);
	if (result.error || (result.status !== 0 && diagnostics.length === 0)) {
		finding(configuration, 1, 1, "error", source, result.error?.message || output.trim().replace(/\s+/g, " ") || `Checker exited with status ${result.status}`);
	}
}

if (await dependenciesReady()) {
	check(process.execPath, [typescript, "--project", configuration, "--pretty", "false"], "TypeScript");
	const sources = luauSources();
	if (sources.length) {
		check(lute, ["check", ...sources], "Lute");
		check(lute, ["lint", ...sources], "Lute lint");
	}
} else {
	finding("dependencies/dependencies.toml", 1, 1, "error", "Preflight", "Dependencies are unavailable. Run workspace dependency setup and check its status-bar output.");
}
