"use strict";
const { test } = require("node:test");
const assert = require("node:assert/strict");
const { seal, sha256, graph, trust, validateOutcomes } = require("./contracts.cjs");

test("content-addressed manifest is stable across object key order", () => {
	const first = seal("operation", { a: 1, z: { c: 3, b: 2 } });
	const second = seal("operation", { z: { b: 2, c: 3 }, a: 1 });
	assert.deepEqual(first, second);
	assert.match(first.digest, /^[a-f0-9]{64}$/);
	assert.equal(sha256("example").length, 64);
});
test("graph allows parallelism and detects invalid edges", () => {
	assert.deepEqual(graph([{ id: "a", needs: [] }, { id: "b", needs: [] }, { id: "c", needs: ["b", "a"] }]), ["a", "b", "c"]);
	assert.throws(() => graph([{ id: "a", needs: ["missing"] }]), /Missing/);
	assert.throws(() => graph([{ id: "a", needs: ["b"] }, { id: "b", needs: ["a"] }]), /cycle/);
});
test("trust classification blocks PR privilege", () => {
	const sha = "a".repeat(40);
	assert.equal(trust("pull_request", "refs/pull/7/merge", "A/B", sha).level, "untrusted");
	assert.equal(trust("push", "refs/heads/source", "A/B", sha).level, "trusted-source");
	assert.equal(trust("workflow_dispatch", "refs/heads/feature", "A/B", sha).level, "untrusted");
});
test("outcome policy does not launder failures or blocking", () => {
	const tasks = [{ id: "a" }, { id: "b" }, { id: "c" }];
	assert.deepEqual(validateOutcomes(tasks, { a: { state: "passed" }, b: { state: "skipped" }, c: { state: "blocked" } }), ["c: blocked"]);
	assert.deepEqual(validateOutcomes(tasks, { a: { state: "passed" }, b: { state: "skipped" }, c: { state: "failed" } }, { b: "failure" }), ["b: skipped", "c: failed"]);
});

test("authored workflow contains only eight linear controller jobs", () => {
	const fs = require("node:fs");
	const path = require("node:path");
	const workflow = fs.readFileSync(path.resolve(__dirname, "../../.github/workflows/ci.yml"), "utf8");
	const jobsSource = workflow.split(/\njobs:\s*\n/)[1];
	assert.ok(jobsSource, "Missing controller jobs");
	const jobs = [...jobsSource.matchAll(/^  ([a-z][a-z0-9_-]*):\s*$/gm)].map(match => match[1]);
	assert.deepEqual(jobs, ["setup", "resolve", "authorize", "generate", "execute", "collect", "cleanup", "validate"]);
	for (let i = 1; i < jobs.length; i++) {
		const start = jobsSource.indexOf("\n  " + jobs[i] + ":");
		const next = jobsSource.indexOf("\n  " + jobs[i + 1] + ":", start);
		const segment = jobsSource.slice(start, next < 0 ? undefined : next);
		assert.match(segment, new RegExp("^    needs: " + jobs[i - 1] + "$", "m"));
	}
	for (const name of ["review", "audit", "build", "tests", "publish"]) {
		assert.ok(!jobs.includes(name), "Operation-specific job leaked into permanent YAML");
	}
	assert.equal((workflow.match(/ci-untrusted/g) || []).length, 3, "Every credential-sensitive stage must use the untrusted environment guard");
});
