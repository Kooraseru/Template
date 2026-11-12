"use strict";

const fs = require("node:fs");
const path = require("node:path");
const { spawnSync } = require("node:child_process");

const root = path.resolve(__dirname, "..");
const maxAnnotations = 50;

function workspacePath(file, workspace = root) {
	if (typeof file !== "string" || !file || file.includes("\0")) return null;
	const relative = path.relative(workspace, path.resolve(workspace, file));
	if (!relative || relative === ".." || relative.startsWith(".." + path.sep) || path.isAbsolute(relative)) return null;
	return relative.split(path.sep).join("/");
}

function diagnosticOutput(output, workspace = root) {
	const found = [];
	for (const line of output.split(/\r?\n/)) {
		if (line.startsWith("::rule-finding::")) {
			let issue;
			try { issue = JSON.parse(line.slice("::rule-finding::".length)); }
			catch { found.push({ file: "ci/code-review.cjs", line: 1, column: 1, severity: "error", source: "Rules", message: "Malformed rule finding", infrastructure: true }); continue; }
			const file = workspacePath(issue.file, workspace);
			const severity = issue.fixtureFailure || issue.checkerFailure ? "error" : issue.severity;
			if (!file || !Number.isInteger(issue.line) || issue.line < 1 || !["error", "warning", "information", "info", "off"].includes(severity)) {
				found.push({ file: "ci/code-review.cjs", line: 1, column: 1, severity: "error", source: "Rules", message: "Invalid rule finding", infrastructure: true });
				continue;
			}
			if (severity !== "off") found.push({
				file, line: issue.line, column: Math.max(1, issue.column || 1),
				severity: severity === "info" ? "information" : severity,
				source: issue.rule || issue.source || "Rules",
				message: String(issue.message || "Rule violation"),
				fixture: !!issue.fixture, infrastructure: !!(issue.fixtureFailure || issue.checkerFailure),
			});
			continue;
		}
		const match = line.match(/^(.*?):(\d+):(\d+): (error|warning|information|info): \[([^\]]+)\] (.*)$/);
		if (!match) continue;
		const file = workspacePath(match[1], workspace);
		found.push({
			file: file || "ci/code-review.cjs", line: file ? Number(match[2]) : 1,
			column: file ? Number(match[3]) : 1, severity: match[4] === "info" ? "information" : match[4],
			source: match[5], message: match[6], infrastructure: !file,
		});
	}
	return found;
}

function changedFiles(base, workspace = root) {
	if (!base) return null;
	if (!/^[A-Za-z0-9][A-Za-z0-9_.\/-]*$/.test(base)) throw new Error("Invalid review base");
	const result = spawnSync("git", ["diff", "--name-only", "-z", "--no-renames", "origin/" + base + "...HEAD", "--"], {
		cwd: workspace, encoding: "utf8", timeout: 15000, maxBuffer: 4 * 1024 * 1024,
	});
	if (result.error || result.status !== 0) throw new Error("Cannot resolve PR changes: " + (result.error?.message || result.stderr || result.status));
	return new Set(result.stdout.split("\0").filter(Boolean).map(file => file.replaceAll("\\", "/")));
}

function review(findings, changed) {
	const all = findings.filter(item => !item.fixture);
	const isChanged = item => item.infrastructure || changed === null || changed.has(item.file);
	const blocking = all.filter(item => item.severity === "error" && isChanged(item));
	const scoped = all.filter(isChanged).sort((a, b) =>
		Number(b.severity === "error") - Number(a.severity === "error") || a.file.localeCompare(b.file) ||
		a.line - b.line || a.column - b.column);
	return { blocking, annotations: scoped.slice(0, maxAnnotations), omitted: Math.max(0, scoped.length - maxAnnotations) };
}

function escapeCommand(value, property = false) {
	let output = String(value).replaceAll("%", "%25").replaceAll("\r", "%0D").replaceAll("\n", "%0A");
	if (property) output = output.replaceAll(",", "%2C").replaceAll(":", "%3A");
	return output;
}

function annotation(item) {
	const level = item.severity === "error" ? "error" : item.severity === "warning" ? "warning" : "notice";
	process.stdout.write("::" + level + " file=" + escapeCommand(item.file, true) +
		",line=" + item.line + ",col=" + item.column + ",title=" + escapeCommand(item.source, true) +
		"::" + escapeCommand(item.message) + "\n");
}

function execute(name, args, workspace = root) {
	process.stdout.write("Code review: running " + name + "\n");
	const result = spawnSync(process.execPath, args, { cwd: workspace, encoding: "utf8", timeout: 150000, maxBuffer: 32 * 1024 * 1024 });
	const output = [result.stdout, result.stderr].filter(Boolean).join("\n");
	const findings = diagnosticOutput(output, workspace);
	if (result.error || (result.status !== 0 && !findings.some(item => item.severity === "error"))) {
		findings.push({
			file: "ci/code-review.cjs", line: 1, column: 1, severity: "error", source: name,
			message: result.error?.message || "Checker failed: " + (output.trim().slice(-500) || "exit code " + result.status),
			infrastructure: true,
		});
	}
	return findings;
}

function summary(findings, checked, base) {
	const actual = findings.filter(item => !item.fixture);
	const count = kind => actual.filter(item => item.severity === kind).length;
	const grouped = new Map();
	for (const finding of actual) {
		const counts = grouped.get(finding.source) || { error: 0, warning: 0, information: 0 };
		counts[finding.severity]++;
		grouped.set(finding.source, counts);
	}
	const rows = [...grouped].sort(([a], [b]) => a.localeCompare(b)).map(([source, counts]) =>
		"| " + source.replaceAll("|", "\\|") + " | " + counts.error + " | " + counts.warning + " | " + counts.information + " |");
	return [
		"## Code review", "",
		"Checked TypeScript, Luau, CI plans, and repository rules without VS Code.",
		"Scope for blocking findings: " + (base ? "changed files in this PR" : "whole repository"),
		"Full repository: " + count("error") + " errors, " + count("warning") + " warnings, " + count("information") + " informational.",
		"Blocking errors: " + checked.blocking.length + ". Inline annotations: " + checked.annotations.length +
			" (" + checked.omitted + " further scoped findings omitted from annotations).",
		"", "| Checker | Errors | Warnings | Information |", "|---|---:|---:|---:|", ...rows, "",
		"Download the code-review-findings artifact for every diagnostic. Expected rule-fixture findings are excluded.", "",
	].join("\n");
}

function main() {
	const dir = path.join(root, "build/code-review");
	fs.mkdirSync(dir, { recursive: true });
	let changed = null, baseFailure = null;
	try { changed = changedFiles(process.env.GITHUB_BASE_REF); }
	catch (error) { baseFailure = String(error.message || error); }
	const findings = [
		...execute("Preflight", ["dependencies/packages/checks/preflightChecker/index.ts", "--ci"]),
		...execute("Rules", ["dependencies/packages/checks/preflightChecker/index.ts", "--rules"]),
	];
	if (baseFailure) findings.push({ file: "ci/code-review.cjs", line: 1, column: 1, severity: "error",
		source: "Code review", message: baseFailure, infrastructure: true });
	const result = review(findings, changed);
	const text = summary(findings, result, process.env.GITHUB_BASE_REF);
	fs.writeFileSync(path.join(dir, "diagnostics.json"), JSON.stringify({
		version: 1, base: process.env.GITHUB_BASE_REF || null, changedFiles: changed ? [...changed].sort() : null,
		diagnostics: findings, blocking: result.blocking.length,
	}, null, 2) + "\n");
	fs.writeFileSync(path.join(dir, "summary.md"), text);
	if (process.env.GITHUB_STEP_SUMMARY) fs.appendFileSync(process.env.GITHUB_STEP_SUMMARY, text);
	for (const item of result.annotations) annotation(item);
	console.log("Code review: " + findings.length + " findings, " + result.blocking.length + " blocking");
	process.exitCode = result.blocking.length ? 1 : 0;
}

module.exports = { workspacePath, diagnosticOutput, changedFiles, review, escapeCommand, summary, main };
if (require.main === module) main();
