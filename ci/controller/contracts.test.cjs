"use strict";
const { test } = require("node:test");
const assert = require("node:assert/strict");
const { seal, sha256, graph, trust, validateOutcomes, validateJobConclusions } = require("./contracts.cjs");

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
test("act tolerates only unresolved chained outputs; never real failures or missing statuses", () => {
	const success = Object.fromEntries(["SETUP", "RESOLVE", "AUTHORIZE", "GENERATE", "RUN", "COLLECT", "CLEANUP"].map(key => ["CI_JOB_" + key, "success"]));
	const unresolved = { ...success, CI_JOB_RESOLVE: "${{ needs.generate.outputs.resolve_result }}", CI_JOB_AUTHORIZE: "${{ needs.generate.outputs.authorize_result }}" };
	assert.deepEqual(validateJobConclusions(success, false), []);
	assert.deepEqual(validateJobConclusions(unresolved, true), []);
	assert.equal(validateJobConclusions(unresolved, false).length, 2);
	assert.deepEqual(validateJobConclusions({ ...unresolved, CI_JOB_RUN: "skipped" }, true), ["Permanent job run did not succeed: skipped"]);
	assert.deepEqual(validateJobConclusions({ ...unresolved, CI_JOB_COLLECT: "failure" }, true), ["Permanent job collect did not succeed: failure"]);
	assert.deepEqual(validateJobConclusions({ ...unresolved, CI_JOB_RUN: "" }, true), ["Permanent job run did not succeed"]);
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


test("read-only generation uses the native Luau workflow DAG and act, not a second scheduler", () => {
	const fs = require("node:fs");
	const path = require("node:path");
	const controller = fs.readFileSync(path.join(__dirname, "stages.cjs"), "utf8");
	assert.match(controller, /ci\/bootstrap\/generateWorkflows\.luau/);
	assert.match(controller, /async function runAct\(pipeline, operation\)/);
	assert.match(controller, /pipeline\.transport === "act"/);
	assert.match(controller, /"push", "--workflows", "\.github\/workflows\/pipeline\.yml"/);
	assert.doesNotMatch(controller, /function runLocal\(/);
	assert.doesNotMatch(controller, /function executeCheck\(/);
	assert.doesNotMatch(controller, /function check\(/);
});
test("lightweight controller stages do not restore a full toolchain or reupload inherited manifests", () => {
	const fs = require("node:fs");
	const path = require("node:path");
	const workflow = fs.readFileSync(path.resolve(__dirname, "../../.github/workflows/ci.yml"), "utf8");
	const ids = ["setup", "resolve", "authorize", "generate", "execute", "collect", "cleanup", "validate"];
	const lines = workflow.split(/\r?\n/);
	const body = {};
	for (let index = 0; index < ids.length; index++) {
		const start = lines.findIndex(line => line === "  " + ids[index] + ":");
		const end = index < ids.length - 1 ? lines.findIndex(line => line === "  " + ids[index + 1] + ":") : lines.length;
		assert.ok(start >= 0 && end > start, "Missing permanent job: " + ids[index]);
		body[ids[index]] = lines.slice(start, end).join("\n");
	}
	for (const id of ["resolve", "collect", "cleanup", "validate"]) {
		assert.doesNotMatch(body[id], /Restore controller dependency archive|Verify and extract common dependencies|actions\/setup-node@/);
	}
	for (const id of ["authorize", "generate", "execute"]) {
		assert.match(body[id], /CI_TOOLCHAIN_DIGEST: \$\{\{ needs\.[a-z]+\.outputs\.toolchain_digest \}\}/);
		assert.match(body[id], /Verify and extract common dependencies/);
	}
	const manifests = { resolve: "operation", authorize: "authorization", generate: "pipeline",
		execute: "execution", collect: "results", cleanup: "cleanup" };
	for (const [id, kind] of Object.entries(manifests)) {
		assert.match(body[id], new RegExp("path: build/ci-controller/artifacts/" + kind + "\\.json"));
	}
	assert.doesNotMatch(body.validate, /Restore controller stage manifests/);
});


test("controller binds downloaded manifest provenance to upstream job output digests", () => {
	const fs = require("node:fs");
	const path = require("node:path");
	const yaml = fs.readFileSync(path.resolve(__dirname, "../../.github/workflows/ci.yml"), "utf8");
	for (const name of ["OPERATION", "AUTHORIZATION", "PIPELINE", "EXECUTION", "RESULTS", "CLEANUP"]) {
		assert.match(yaml, new RegExp("CI_" + name + "_DIGEST: \\$\\{\\{ needs\\."));
	}
	for (const key of ["operation_digest", "authorization_digest", "pipeline_digest", "execution_digest", "results_digest"]) {
		assert.match(yaml, new RegExp("^      " + key + ": \\$\\{\\{ needs\\.", "m"));
	}
	assert.match(yaml, /CI_CLEANUP_DIGEST: \$\{\{ needs\.cleanup\.outputs\.digest \}\}/);
});


test("PR-controlled operation outputs cannot select protected credentials", () => {
	const fs = require("node:fs");
	const path = require("node:path");
	const source = fs.readFileSync(path.resolve(__dirname, "../../.github/workflows/ci.yml"), "utf8");
	const jobs = ["execute", "collect", "cleanup", "validate"];
	const lines = source.split(/\r?\n/);
	const chunks = Object.fromEntries(jobs.map((job, index) => {
		const start = lines.findIndex(line => line === "  " + job + ":");
		const next = index < jobs.length - 1 ? lines.findIndex(line => line === "  " + jobs[index + 1] + ":") : lines.length;
		assert.ok(start >= 0 && next > start);
		return [job, lines.slice(start, next).join("\n")];
	}));
	for (const job of ["execute", "cleanup"]) {
		for (const binding of ["CI_CREDENTIAL_APP_ID", "CI_CREDENTIAL_APP_PRIVATE_KEY", "CI_CREDENTIAL_BOOTSTRAP_TOKEN"]) {
			const line = chunks[job].split("\n").find(text => text.includes(binding + ":"));
			assert.ok(line && line.includes("github.event_name != 'pull_request'") &&
				line.includes("github.ref == 'refs/heads/source'") && line.includes("outputs.mode == 'generated'"),
				"Untrusted PR may access " + binding + " in " + job);
		}
	}
	for (const job of ["execute", "collect", "cleanup"]) {
		assert.match(chunks[job], /outputs\.mode == 'generated'/);
	}
});
