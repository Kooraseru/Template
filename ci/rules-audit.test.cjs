"use strict";
const test = require("node:test");
const assert = require("node:assert/strict");
const { diagnosticOutput, review } = require("./code-review.cjs");
const { summary } = require("./rules-audit.cjs");

test("Rules Audit retains warnings but only changed-file errors block the PR gate", () => {
	const lines = [
		{ file: "ci/new.luau", line: 1, severity: "warning", rule: "luau/blank-lines", message: "Style warning" },
		{ file: "ci/old.luau", line: 2, severity: "error", rule: "luau/documentation", message: "Existing issue" },
		{ file: "ci/new.luau", line: 3, severity: "error", rule: "luau/naming", message: "Violation" },
		{ file: "rules/luau/naming/tests/invalid/example.luau", line: 1, severity: "error", fixture: true, rule: "luau/naming", message: "Expected fixture" },
	].map(item => "::rule-finding::" + JSON.stringify(item)).join("\n");
	const findings = diagnosticOutput(lines, "/tmp/rules-audit-fixture");
	const result = review(findings, new Set(["ci/new.luau"]));
	assert.equal(result.blocking.length, 1);
	assert.equal(result.annotations.length, 2);
	const report = summary(findings, result, "source");
	assert.match(report, /Full repository: 2 errors, 1 warnings/);
	assert.match(report, /Warnings are advisory/);
});
