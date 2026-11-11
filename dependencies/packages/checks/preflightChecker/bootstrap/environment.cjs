"use strict";

const { execFileSync, spawn } = require("node:child_process");
const fs = require("node:fs");
const os = require("node:os");
const path = require("node:path");
const { randomUUID } = require("node:crypto");

const targets = new Set(["work/labels/sync", "governance/branches/publish"]);
const runner = "dependencies/packages/checks/preflightChecker/bootstrap/rehearsal.cjs";
const { executeServiceRehearsal } = require("../../../../../dependencies/managed/npm/node_modules/preflight/src/rehearsal.js");

function extraFiles(workspace) {
	return execFileSync("git", ["ls-files", "-z", "--others", "--exclude-standard", "--",
		"ci", ".github/config", ".github/docs", "dependencies/packages"], { cwd: workspace, encoding: "utf8" })
		.split("\0").filter(Boolean);
}

function stage(workspace, snapshot) {
	const tracked = execFileSync("git", ["ls-files", "-z", "--cached"], { cwd: workspace, encoding: "utf8" });
	for (const name of new Set([...tracked.split("\0").filter(Boolean), ...extraFiles(workspace)])) {
		if (/(^|\/)(\.git|\.env(?:\.[^/]*)?|\.npmrc|\.netrc|\.gitconfig)(\/|$)|\.(pem|key|p12|pfx)$/i.test(name)) continue;
		const source = path.join(workspace, name);
		if (!fs.existsSync(source)) continue;
		const relative = path.relative(workspace, fs.realpathSync(source));
		if (relative.startsWith(".." + path.sep) || path.isAbsolute(relative) ||
			!fs.lstatSync(source).isFile()) throw new Error("Unsafe staged path");
		const destination = path.join(snapshot, name);
		fs.mkdirSync(path.dirname(destination), { recursive: true });
		fs.copyFileSync(source, destination);
	}
}

async function execute({ steps, workspace, entry, profile, signal, onStep }) {
	const selected = steps.at(-1)?.id;
	const skip = reason => {
		for (const { id } of steps) onStep({ id, status: "skipped", reason, durationMs: 0 });
		return { incomplete: true };
	};
	if (entry !== "push" || !targets.has(selected) || !profile?.image) {
		return skip("Select a supported push publication target and supply a rehearsal image.");
	}
	if (executeServiceRehearsal) {
		return executeServiceRehearsal({ workspace, steps, signal, onStep }, {
			image: profile.image, command: ["node", runner], files: extraFiles(workspace),
			input: { scenario: profile.scenario ?? "create" },
		});
	}
	// The pinned package predates the reusable service runner.
	const snapshot = fs.mkdtempSync(path.join(os.tmpdir(), "template-preflight-"));
	const container = "template-preflight-" + randomUUID();
	try {
		stage(workspace, snapshot);
		const result = await new Promise(resolve => {
			const child = spawn("docker", [
				"run", "--rm", "-i", "--name", container, "--pull", "never", "--network", "none",
				"--cap-drop", "ALL", "--security-opt", "no-new-privileges",
				"--mount", `type=bind,source=${snapshot},target=/snapshot,readonly`,
				profile.image, "sh", "-ec",
				"mkdir /workspace; cp -R /snapshot/. /workspace; cd /workspace; exec node dependencies/packages/checks/preflightChecker/bootstrap/rehearsal.cjs",
			], { signal, stdio: ["pipe", "pipe", "ignore"] });
			let output = "";
			child.stdout.setEncoding("utf8").on("data", chunk => { output += chunk; });
			child.stdin.on("error", () => {});
			child.stdin.end(JSON.stringify({ steps, scenario: profile.scenario ?? "create" }));
			const timer = setTimeout(() => child.kill(), 180_000);
			child.on("error", () => {});
			child.on("close", code => {
				clearTimeout(timer);
				resolve(code === 0 ? output : null);
			});
		});
		if (!result) return skip("Rehearsal container unavailable, interrupted, or unable to start.");
		const outcomes = JSON.parse(result);
		for (const outcome of outcomes) onStep(outcome);
		return { incomplete: outcomes.some(outcome => outcome.status === "skipped") };
	} finally {
		try {
			execFileSync("docker", ["rm", "-f", container], { stdio: "ignore", timeout: 15_000 });
		} catch {}
		fs.rmSync(snapshot, { recursive: true, force: true });
	}
}

module.exports = { id: "template-offline-publication", execute };
