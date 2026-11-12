"use strict";
const test = require("node:test");
const assert = require("node:assert/strict");
const { workspacePath, diagnosticOutput, review, escapeCommand, summary } = require("./code-review.cjs");

test("compiler diagnostics retain source locations without accepting escaped paths", () => {
	const root = "/tmp/review-fixture";
	assert.equal(workspacePath("ci/entry.luau", root), "ci/entry.luau");
	assert.equal(workspacePath("../secrets.txt", root), null);
	const found = diagnosticOutput("/tmp/review-fixture/ci/entry.luau:12:4: error: [Lute] Unknown global foo", root);
	assert.deepEqual(found[0], { file: "ci/entry.luau", line: 12, column: 4, severity: "error",
		source: "Lute", message: "Unknown global foo", infrastructure: false });
});

test("rule findings preserve severity and exclude expected fixture diagnostics", () => {
	const root = "/tmp/review-fixture";
	const log = [
		{ file: "ci/entry.luau", line: 2, column: 1, rule: "luau/naming", severity: "warning", message: "warning" },
		{ file: "rules/luau/naming/tests/invalid/fixture.luau", line: 1, column: 1, rule: "luau/naming", severity: "information", fixture: true, message: "expected" },
		{ file: "ci/entry.luau", line: 4, column: 1, rule: "luau/naming", severity: "error", checkerFailure: true, message: "checker failed" },
	].map(line => "::rule-finding::" + JSON.stringify(line)).join("\n");
	const found = diagnosticOutput(log, root);
	assert.equal(found.length, 3);
	const result = review(found, new Set(["ci/entry.luau"]));
	assert.equal(result.annotations.length, 2);
	assert.equal(result.blocking.length, 1);
	assert.match(summary(found, result, "source"), /Repository Rules have a separate audit/);
});

test("pre-existing errors are in the full report but do not block unrelated PRs", () => {
	const found = [{ file: "ci/old.luau", line: 1, column: 1, severity: "error", source: "Lute", message: "existing" }];
	assert.equal(review(found, new Set(["ci/new.luau"])).blocking.length, 0);
	assert.equal(review(found, null).blocking.length, 1);
	assert.equal(review([{ ...found[0], infrastructure: true }], new Set()).blocking.length, 1);
});

test("annotation text escapes GitHub workflow commands safely", () => {
	assert.equal(escapeCommand("a,b%c\n", true), "a%2Cb%25c%0A");
	assert.equal(escapeCommand("a\nb"), "a%0Ab");
});
