"use strict";

const fs = require("node:fs");
const path = require("node:path");
const { execute, changedFiles, review, annotation } = require("./code-review.cjs");
const root = path.resolve(__dirname, "..");

function summary(findings, checked, base) {
	const active = findings.filter(item => !item.fixture);
	const count = severity => active.filter(item => item.severity === severity).length;
	const groups = new Map();
	for (const item of active) {
		const group = groups.get(item.source) || { error: 0, warning: 0, information: 0 };
		group[item.severity] += 1;
		groups.set(item.source, group);
	}
	const rows = [...groups].sort(([a], [b]) => a.localeCompare(b)).map(([source, counts]) =>
		"| " + source.replaceAll("|", "\\|") + " | " + counts.error + " | " + counts.warning + " | " + counts.information + " |");
	return [
		"## Rules Audit", "",
		"Audits repository rules independently of Code Review and Preflight.",
		"Blocking scope: " + (base ? "PR-changed files plus checker/fixture infrastructure errors" : "whole repository") + ".",
		"Full repository: " + count("error") + " errors, " + count("warning") + " warnings, " + count("information") + " informational.",
		"Blocking errors: " + checked.blocking.length + ". Inline annotations: " + checked.annotations.length +
			" (" + checked.omitted + " further scoped findings omitted).", "",
		"| Rule | Errors | Warnings | Information |", "|---|---:|---:|---:|", ...rows, "",
		"Warnings are advisory. Expected rule-fixture findings are excluded. Download rules-audit-findings for every diagnostic.", "",
	].join("\n");
}

function main() {
	const directory = path.join(root, "build/rules-audit");
	fs.mkdirSync(directory, { recursive: true });
	let changed = null, baseFailure = null;
	try { changed = changedFiles(process.env.GITHUB_BASE_REF); }
	catch (error) { baseFailure = String(error.message || error); }
	const findings = execute("Rules", ["dependencies/packages/checks/preflightChecker/index.ts", "--rules"], root, "Rules audit");
	if (baseFailure) findings.push({
		file: "ci/rules-audit.cjs", line: 1, column: 1, severity: "error",
		source: "Rules Audit", message: baseFailure, infrastructure: true,
	});
	const checked = review(findings, changed);
	fs.writeFileSync(path.join(directory, "diagnostics.json"), JSON.stringify({
		version: 1, audit: "rules", base: process.env.GITHUB_BASE_REF || null,
		changedFiles: changed ? [...changed].sort() : null, diagnostics: findings, blocking: checked.blocking.length,
	}, null, 2) + "\n");
	const report = summary(findings, checked, process.env.GITHUB_BASE_REF);
	fs.writeFileSync(path.join(directory, "summary.md"), report);
	if (process.env.GITHUB_STEP_SUMMARY) fs.appendFileSync(process.env.GITHUB_STEP_SUMMARY, report);
	for (const item of checked.annotations) annotation(item);
	console.log("Rules audit: " + findings.length + " findings, " + checked.blocking.length + " blocking");
	process.exitCode = checked.blocking.length ? 1 : 0;
}

module.exports = { summary, main };
if (require.main === module) main();
