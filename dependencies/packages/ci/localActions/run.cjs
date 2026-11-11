"use strict";
const fs = require("node:fs");
const path = require("node:path");
const crypto = require("node:crypto");
const { spawnSync, execFileSync } = require("node:child_process");
const artifacts = require("./artifacts.cjs");
const root = path.resolve(__dirname, "../../../..");

function operationFile(file) {
	const text = fs.readFileSync(path.resolve(root, file), "utf8");
	const match = text.match(/^\s*(?:export\s+)?operation\s*=\s*(?:"([^"\r\n]*)"|'([^'\r\n]*)'|([^#\s]*))/m);
	return match ? match[1] ?? match[2] ?? match[3] : undefined;
}
function options(args) {
	const informational = args.some(arg => ["--help", "-h", "--version", "--list", "-l"].includes(arg));
	if (informational) return { informational: true, operation: "validation", event: "workflow_dispatch", args };
	const values = new Set(["-W", "--workflows", "-e", "--eventpath", "--input-file", "--secret-file", "--var-file", "--env-file", "--input", "--env", "--secret", "--var", "-P", "--platform", "-j", "--job", "--container-architecture", "--artifact-server-port", "--artifact-server-path", "--actor", "--remote-name", "--network", "--container-options", "--container-daemon-socket", "--action-cache-path", "--concurrent-jobs", "--github-instance", "--matrix", "-s"]);
	const events = new Set(["push", "pull_request", "workflow_dispatch"]);
	let event, operation, payloadOperation, fileOperation = fs.existsSync(path.join(root, ".input")) ? operationFile(".input") : undefined;
	for (let index = 0; index < args.length; index++) {
		const arg = args[index];
		if (events.has(arg)) event = arg;
		if (arg === "--input-file") fileOperation = args[index + 1] ? operationFile(args[index + 1]) : undefined;
		if ((arg === "-e" || arg === "--eventpath") && args[index + 1]) payloadOperation = JSON.parse(fs.readFileSync(path.resolve(root, args[index + 1]), "utf8")).inputs?.operation;
		if (arg.startsWith("--input-file=")) fileOperation = arg.slice(13) ? operationFile(arg.slice(13)) : undefined;
		if (arg.startsWith("--eventpath=") && arg.slice(12)) payloadOperation = JSON.parse(fs.readFileSync(path.resolve(root, arg.slice(12)), "utf8")).inputs?.operation;
		const input = arg.startsWith("--input=") ? arg.slice(8) : arg === "--input" ? args[index + 1] : undefined;
		if (input?.startsWith("operation=")) operation = input.slice(10);
		if (values.has(arg)) index++;
	}
	operation ??= fileOperation ?? payloadOperation ?? (event === "push" ? "build" : "validation");
	if (!["validation", "build", "readiness"].includes(operation)) throw new Error("Unknown CI operation: " + operation);
	if (event === "pull_request" && operation !== "validation") throw new Error("Pull requests permit Validation only");
	return { informational, operation, event: event || "workflow_dispatch", args: event ? args : ["workflow_dispatch", ...args] };
}
function main(args = process.argv.slice(2)) {
	const selected = options(args);
	const check = spawnSync("act", ["--version"], { cwd: root, encoding: "utf8", windowsHide: true });
	if (check.error) throw new Error("act is unavailable on PATH. Install act and restart the terminal/editor environment.");
	if (selected.informational) return spawnSync("act", selected.args, { cwd: root, stdio: "inherit", windowsHide: true }).status ?? 1;
	if (!fs.existsSync(path.join(root, ".actrc"))) throw new Error("Run workspace dependency setup to generate .actrc");
	const runId = crypto.randomUUID(), runRoot = artifacts.target(root, "build/run/" + runId);
	const source = execFileSync("git", ["rev-parse", "HEAD"], { cwd: root, encoding: "utf8", windowsHide: true }).trim();
	const { tracked, files: snapshot, digest: workspaceDigest } = artifacts.snapshot(root);
	const directory = path.join(root, ".workspace/ci/runs"); fs.mkdirSync(directory, { recursive: true }); fs.mkdirSync(runRoot, { recursive: true });
	const file = path.join(directory, runId + ".json");
	const record = { version: 2, id: runId, runner: "act", scope: "pipeline", operation: selected.operation, source, workspaceDigest, state: "running", pid: process.pid, startedAt: new Date().toISOString(), stages: { start: "running", [selected.operation]: "pending", publish: "disabled" }, runDirectory: path.relative(root, runRoot).replaceAll("\\", "/") };
	function publish() { fs.writeFileSync(file + ".tmp", JSON.stringify(record)); fs.renameSync(file + ".tmp", file); }
	function execute(argv, cwd, log) {
		const descriptor = fs.openSync(path.join(runRoot, log), "w");
		const result = spawnSync("act", argv, { cwd, windowsHide: true, stdio: ["ignore", descriptor, descriptor], env: { ...process.env, CI_LOCAL_RUN_ID: runId } });
		fs.closeSync(descriptor);
		if (result.error || result.status !== 0) throw new Error(result.error?.message || `act exited with status ${result.status}; see ${record.runDirectory}/${log}`);
	}
	const transport = path.join(runRoot, "transport");
	const port = execFileSync(process.execPath, ["-e", "const s=require('net').createServer();s.listen(0,()=>{console.log(s.address().port);s.close()})"], { encoding: "utf8", windowsHide: true }).trim();
	const readToken = selected.operation === "readiness" && args.some((arg, index) => arg.startsWith("--secret=GITHUB_TOKEN=") || ((arg === "--secret" || arg === "-s") && (args[index + 1] === "GITHUB_TOKEN" || args[index + 1]?.startsWith("GITHUB_TOKEN="))));
	const runtimeArgs = [...(readToken ? ["--secret-file", ""] : ["--secret-file", "", "--secret", "GITHUB_TOKEN="]),"--env", "CI_WORKSPACE_DIGEST=" + workspaceDigest,"--artifact-server-path", transport, "--artifact-server-port", port, "--env", "CI_LOCAL_RUN_ID=" + runId];
	let worktree, failureStage = "start";
	publish();
	try {
		console.log(`Start ${selected.operation}: ${record.runDirectory}`);
		worktree = path.join(runRoot, "worktree");
		execFileSync("git", ["clone", "--no-hardlinks", "--no-checkout", root, worktree], { windowsHide: true, stdio: "pipe" });
		execFileSync("git", ["checkout", "--detach", source], { cwd: worktree, windowsHide: true, stdio: "pipe" });
		const origin = execFileSync("git", ["remote", "get-url", "origin"], { cwd: root, encoding: "utf8", windowsHide: true }).trim();
		execFileSync("git", ["remote", "set-url", "origin", origin], { cwd: worktree, windowsHide: true });
		const priorFiles = execFileSync("git", ["ls-files", "-z"], { cwd: worktree }).toString().split("\0").filter(Boolean);
		for (const name of priorFiles) if (!tracked.includes(name)) fs.rmSync(artifacts.target(worktree, name), { force: true });
		for (const [name, bytes] of snapshot) { const file = artifacts.target(worktree, name); if (bytes === null) fs.rmSync(file, { force: true }); else { fs.mkdirSync(path.dirname(file), { recursive: true }); fs.writeFileSync(file, bytes); } }
		fs.copyFileSync(path.join(worktree, ".vscode/config/act/actrc"), path.join(worktree, ".actrc"));
		execFileSync("git", ["add", "-A"], { cwd: worktree, windowsHide: true, stdio: "pipe" });
		const startArgs = [...selected.args];
		const files = new Set(["--input-file", "--secret-file", "--var-file", "--env-file", "--eventpath", "-e"]);
		for (let i = 0; i < startArgs.length; i++) if (files.has(startArgs[i])) { if (startArgs[i + 1]) startArgs[i + 1] = path.resolve(root, startArgs[i + 1]); i++; }
		execute([...startArgs, ...runtimeArgs], worktree, "start.log");
		record.stages.start = "passed";
		if (selected.operation !== "readiness") {
			const generated = artifacts.receiveStart(runRoot);
			const plan = JSON.parse(fs.readFileSync(path.join(generated, "plan.json"), "utf8"));
			failureStage = selected.operation; record.stages[selected.operation] = "running"; publish();
			for (const entry of fs.readdirSync(generated)) if (entry.endsWith(".yml")) fs.copyFileSync(path.join(generated, entry), path.join(worktree, ".github/workflows", entry));
			execFileSync("git", ["add", "-A"], { cwd: worktree, windowsHide: true, stdio: "pipe" });
			// Preserve the caller's platform/offline/container flags. Event, input and workflow selection belong to Start.
			const executionArgs = [];
			const excluded = new Set(["-W", "--workflows", "--input", "--input-file", "-e", "--eventpath", "-j", "--job", "--artifact-server-path", "--artifact-server-port"]);
			for (let i = 0; i < args.length; i++) { if (excluded.has(args[i])) { i++; continue; } if (/^(push|pull_request|workflow_dispatch)$/.test(args[i]) || /^--(input|workflows|eventpath|artifact-server-path|artifact-server-port)=/.test(args[i])) continue; executionArgs.push(args[i]); }
			execute(["push", "--workflows", ".github/workflows/pipeline.yml", ...executionArgs, ...runtimeArgs], worktree, "execution.log");
			record.stages[selected.operation] = "passed";
			artifacts.receiveDiagnostics(runRoot);
			record.reports = record.runDirectory + "/" + selected.operation;
			failureStage = "export"; record.stages.export = "running"; publish();
			const tasks = plan.filter(task => task.phase === "build");
			const manifest = artifacts.exportOutputs(runRoot, { runId, source, workspaceDigest, operation: selected.operation, components: tasks.map(task => task.identity), tasks });
			artifacts.promote(root, runRoot, manifest);
			record.stages.export = "passed";
			record.artifacts = record.runDirectory + "/outputs"; record.manifest = record.artifacts + "/manifest.json";
		} else record.stages.readiness = "passed";
		record.state = "passed"; record.exitCode = 0;
		console.log(`Completed ${selected.operation}; readable outputs: ${record.artifacts || record.runDirectory}`);
	} catch (error) {
		try { artifacts.receiveDiagnostics(runRoot); } catch (failure) { record.diagnosticsFailure = failure.message.slice(0, 500); }
		for (const stage of Object.keys(record.stages)) if (record.stages[stage] === "pending") record.stages[stage] = "blocked";
		record.state = "failed"; record.exitCode = 1; record.failureStage = failureStage; record.stages[failureStage] = "failed"; record.failure = error.message.slice(0, 1000); console.error(record.failure);
	} finally {
		if (worktree) {
			const checked = artifacts.target(root, record.runDirectory + "/worktree");
			if (checked !== path.resolve(worktree) || fs.lstatSync(checked, { throwIfNoEntry: false })?.isSymbolicLink()) record.cleanup = "Isolated checkout retained for inspection";
			else fs.rmSync(checked, { recursive: true, force: true });
		}
		record.finishedAt = new Date().toISOString(); publish();
	}
	return record.exitCode;
}
module.exports = { options, main };
if (require.main === module) { try { process.exitCode = main(); } catch (error) { console.error(error.message); process.exitCode = 1; } }
