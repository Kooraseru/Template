"use strict";

// Non-secret, content-addressed contracts passed between the permanent CI jobs.
const fs = require("node:fs");
const path = require("node:path");
const crypto = require("node:crypto");
const ROOT = path.resolve(__dirname, "../..");
const STATE = path.join(ROOT, "build/ci-controller");
const ARTIFACTS = path.join(STATE, "artifacts");
const TYPES = new Set(["operation", "authorization", "pipeline", "execution", "results", "cleanup"]);
const HEX = /^[a-f0-9]{64}$/;
const SAFE = /^[a-zA-Z0-9][a-zA-Z0-9._/-]*$/;

function assert(test, reason) {
	if (!test) throw new Error(reason);
}
function sha256(data) {
	return crypto.createHash("sha256").update(data).digest("hex");
}
function canonical(value) {
	if (Array.isArray(value)) return value.map(canonical);
	if (value && typeof value === "object") {
		return Object.fromEntries(Object.keys(value).sort().map(key => [key, canonical(value[key])]));
	}
	return value;
}
function artifactPath(kind) {
	assert(TYPES.has(kind), "Unknown controller manifest kind");
	return path.join(ARTIFACTS, kind + ".json");
}
function seal(kind, value) {
	assert(TYPES.has(kind), "Unknown controller manifest kind");
	const payload = canonical({ version: 1, kind, ...value });
	const digest = sha256(JSON.stringify(payload));
	return { ...payload, digest };
}
function write(kind, value) {
	const sealed = seal(kind, value);
	const filename = artifactPath(kind);
	fs.mkdirSync(path.dirname(filename), { recursive: true });
	fs.writeFileSync(filename, JSON.stringify(sealed, null, 2) + "\n", { mode: 0o600 });
	return sealed;
}
function read(kind, expectedDigest) {
	const source = JSON.parse(fs.readFileSync(artifactPath(kind), "utf8"));
	const { digest, ...payload } = source;
	assert(digest && HEX.test(digest), "Malformed " + kind + " digest");
	assert(payload.version === 1 && payload.kind === kind, "Wrong manifest type: " + kind);
	assert(sha256(JSON.stringify(canonical(payload))) === digest, "Tampered " + kind + " manifest");
	if (expectedDigest) assert(digest === expectedDigest, "Unexpected " + kind + " digest");
	return source;
}
function output(values) {
	const filename = process.env.GITHUB_OUTPUT;
	if (!filename) return;
	for (const [key, value] of Object.entries(values)) {
		assert(/^[a-z_][a-z0-9_]*$/.test(key), "Unsafe output name");
		const text = String(value);
		assert(!/[\r\n\u0000]/.test(text), "Unsafe output value");
		fs.appendFileSync(filename, key + "=" + text + "\n");
	}
}
function safeRef(value) {
	assert(typeof value === "string" && SAFE.test(value) && !value.includes("..") && !value.includes("//"), "Unsafe ref");
	return value;
}
function trust(event, ref, repository, sha) {
	assert(["push", "pull_request", "workflow_dispatch"].includes(event), "Unsupported event");
	assert(typeof repository === "string" && /^[\w.-]+\/[\w.-]+$/.test(repository), "Invalid repository");
	assert(typeof sha === "string" && /^[\da-f]{40}$/.test(sha), "Invalid source SHA");
	const trusted = event !== "pull_request" && ref === "refs/heads/source";
	return { event, ref, repository, sha, level: trusted ? "trusted-source" : "untrusted" };
}
function graph(tasks) {
	assert(Array.isArray(tasks) && tasks.length > 0, "Pipeline requires at least one component");
	const ids = new Map();
	for (const task of tasks) {
		assert(task && /^[a-z][a-z0-9_/-]*$/.test(task.id) && !ids.has(task.id), "Duplicate or invalid component");
		assert(Array.isArray(task.needs), "Missing dependency list for " + task.id);
		ids.set(task.id, task);
	}
	const order = [];
	const visitState = new Map();
	function visit(id) {
		assert(ids.has(id), "Missing pipeline dependency: " + id);
		if (visitState.get(id) === 1) throw new Error("Pipeline dependency cycle at " + id);
		if (visitState.get(id) === 2) return;
		visitState.set(id, 1);
		for (const required of ids.get(id).needs) {
			assert(required !== id, "Self-dependent component: " + id);
			visit(required);
		}
		visitState.set(id, 2);
		order.push(id);
	}
	for (const id of ids.keys()) visit(id);
	return order;
}
function validateOutcomes(tasks, outcomes, allowedSkips = {}) {
	const failures = [];
	for (const task of tasks) {
		const outcome = outcomes[task.id];
		if (!outcome || !["passed", "failed", "skipped", "cancelled", "blocked"].includes(outcome.state)) {
			failures.push(task.id + ": missing or invalid outcome");
			continue;
		}
		if (outcome.state === "passed") continue;
		if (outcome.state === "skipped" && (allowedSkips[task.id] || "neutral") !== "failure") continue;
		failures.push(task.id + ": " + outcome.state);
	}
	return failures;
}
function validateJobConclusions(env, localAct = false) {
	const failures = [];
	for (const key of ["SETUP", "RESOLVE", "AUTHORIZE", "GENERATE", "RUN", "COLLECT", "CLEANUP"]) {
		const state = env["CI_JOB_" + key];
		if (state === "success") continue;
		// act does not always evaluate nested job outputs. The verified stage manifests
		// remain mandatory, so only an unresolved expression may be deferred locally.
		if (localAct && typeof state === "string" && /^\\$\\{\\{[^{}]+\\}\\}$/.test(state)) continue;
		failures.push("Permanent job " + key.toLowerCase() + " did not succeed" + (state ? ": " + state : ""));
	}
	return failures;
}
module.exports = { ROOT, STATE, ARTIFACTS, TYPES, assert, sha256, canonical, artifactPath,
	seal, write, read, output, safeRef, trust, graph, validateOutcomes, validateJobConclusions };
