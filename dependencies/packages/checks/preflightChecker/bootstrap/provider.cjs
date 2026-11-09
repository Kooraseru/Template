"use strict";

const path = require("node:path");
const { execFile } = require("node:child_process");
const { promisify } = require("node:util");

const execute = promisify(execFile);

function list(value) {
	return Array.isArray(value) ? value : [];
}

async function resolve({ workspace, entry = "pull_request", signal }) {
	const binary = process.platform === "win32" ? "lute.exe" : "lute";
	const runtime = path.join(workspace, "build", "dependencies", "bin", "lute", binary);
	const { stdout } = await execute(runtime, ["run", "dependencies/packages/checks/preflightChecker/bootstrap/plan.luau", entry], {
		cwd: workspace,
		signal,
		timeout: 30_000,
		maxBuffer: 4 * 1024 * 1024,
	});
	const tasks = JSON.parse(stdout);
	return {
		entry,
		steps: tasks.map(task => ({
			id: task.identity,
			needs: list(task.needs),
			inputs: list(task.inputs),
			outputs: list(task.outputs),
			command: ["lute", "run", task.invoker, task.entry, entry],
			effects: [task.boundary === "privileged" || list(task.credentials).length ? "external" : "local"],
			requirements: { tools: ["lute"], credentials: list(task.credentials) },
		})),
	};
}

module.exports = { resolve };
