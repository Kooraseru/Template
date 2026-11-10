"use strict";
const fs = require("node:fs");
const path = require("node:path");
const crypto = require("node:crypto");
const { spawnSync } = require("node:child_process");

const root = path.resolve(__dirname, "../../../..");
const config = fs.readFileSync(path.join(root, ".vscode/config/act/actrc"), "utf8");
const args = config.split(/\r?\n/).map(line => line.trim()).filter(line => line && !line.startsWith("#"));
const directory = path.join(root, ".workspace/ci/runs");
fs.mkdirSync(directory, { recursive: true });
const file = path.join(directory, crypto.randomUUID() + ".json");
const record = { version: 1, runner: "act", state: "running", pid: process.pid, startedAt: new Date().toISOString(), scope: "invocation", workflowState: "unavailable" };
function publish() {
	const temporary = file + ".tmp";
	fs.writeFileSync(temporary, JSON.stringify(record));
	fs.renameSync(temporary, file);
}
publish();
const result = spawnSync("act", [...args, ...process.argv.slice(2)], { cwd: root, stdio: "inherit", windowsHide: true });
Object.assign(record, { state: !result.error && result.status === 0 ? "passed" : "failed", finishedAt: new Date().toISOString(), exitCode: result.status, failure: result.error?.message || (result.status !== 0 ? `act exited with status ${result.status}; inspect the local CI terminal and build/run logs for component details` : undefined) });
publish();
if (result.error) console.error(result.error.message);
process.exitCode = result.status ?? 1;
