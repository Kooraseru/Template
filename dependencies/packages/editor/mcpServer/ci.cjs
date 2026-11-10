"use strict";
const fs = require("node:fs");
const path = require("node:path");
const { createRequire } = require("node:module");

function getStatus({ root, limit = 5 }) {
	if (!Number.isInteger(limit) || limit < 1 || limit > 20) throw new Error("ci_get_status: limit must be 1..20");
	const workflows = [];
	const issues = [];
	try {
		const { parse } = createRequire(path.join(root, "dependencies/managed/npm/package.json"))("yaml");
		const directory = path.join(root, ".github/workflows");
		for (const name of fs.readdirSync(directory).filter(name => /\.ya?ml$/.test(name)).sort()) {
			const value = parse(fs.readFileSync(path.join(directory, name), "utf8"));
			workflows.push({ name: value.name || name, file: ".github/workflows/" + name, state: "unavailable", reason: "Workflow declarations do not expose local extension execution state." });
		}
	} catch (error) { issues.push("Workflow discovery unavailable: " + error.message); }
	const directory = path.join(root, ".workspace/ci/runs");
	const files = fs.existsSync(directory) ? fs.readdirSync(directory).filter(name => /^[a-f0-9-]+\.json$/.test(name)) : [];
	const records = [];
	for (const file of files) {
		try {
			const full = path.join(directory, file);
			if (fs.lstatSync(full).isSymbolicLink() || fs.statSync(full).size > 16000) throw new Error("Invalid execution record");
			const value = JSON.parse(fs.readFileSync(full, "utf8"));
			if (value.version !== 1 || value.runner !== "act" || !["running", "passed", "failed"].includes(value.state) || !Number.isFinite(Date.parse(value.startedAt))) throw new Error("Invalid execution record");
			let state = value.state;
			if (state === "running") {
				try { if (!Number.isInteger(value.pid) || value.pid < 1) throw new Error(); process.kill(value.pid, 0); }
				catch (error) { if (error.code !== "EPERM") state = "unknown"; }
			}
			records.push({ id: file.slice(0, -5), runner: "act", scope: "invocation", state, startedAt: value.startedAt,
				finishedAt: value.finishedAt, exitCode: value.exitCode, failure: typeof value.failure === "string" ? value.failure.slice(0, 1000) : undefined,
				...(state === "unknown" ? { reason: "Recorder stopped before recording completion; rerun local CI to establish a fresh result." } : {}) });
		} catch { issues.push("Unreadable CI execution record: " + file); }
	}
	records.sort((a, b) => b.startedAt.localeCompare(a.startedAt));
	return { available: records.length > 0, workflows, executions: records.slice(0, limit), total: records.length, truncated: records.length > limit, issues: issues.slice(0, 5), issueCount: issues.length,
		note: "Recorded local act invocations only; per-workflow and private extension history are unavailable. Run the existing local Actions task to record an execution. Results may refer to older source; no current-revision success is implied." };
}
module.exports = { getStatus };
