"use strict";

const { spawnSync } = require("node:child_process");
const { createHash } = require("node:crypto");
const fs = require("node:fs");
const path = require("node:path");

const root = path.resolve(__dirname, "../..");

function readProblems() {
	const client = path.join(root, "dependencies/packages/editorIntegration/client.cjs");
	const env = { ...process.env };
	if (!env.WORKBENCH_BRIDGE_SESSION) {
		const selection = path.join(root, "build/run/editor-problems/session-file.txt");
		if (fs.existsSync(selection)) env.WORKBENCH_BRIDGE_SESSION = fs.readFileSync(selection, "utf8").trim();
	}
	const result = spawnSync(process.execPath, [client, "--problems"], {
		cwd: root,
		env,
		encoding: "utf8",
		timeout: 4000,
		maxBuffer: 8 * 1024 * 1024,
		windowsHide: true,
	});
	if (result.stderr?.includes("Multiple VS Code sessions match this workspace")) {
		throw new Error("Multiple VS Code sessions match. Select a Workbench Bridge session explicitly.");
	}
	if (result.error || result.status !== 0) throw new Error("Workbench Bridge did not return a snapshot.");
	const problems = JSON.parse(result.stdout);
	if (!Array.isArray(problems)) throw new Error("Invalid Problems snapshot");
	return problems;
}

function signature(problem) {
	return JSON.stringify([problem.file, problem.severity, problem.source, problem.code, problem.message]);
}

function emit(event, context) {
	console.log(JSON.stringify({ hookSpecificOutput: { hookEventName: event, additionalContext: context } }));
}

function main(input) {
	const event = input.hook_event_name;
	const starting = event === "SessionStart";
	const before = event === "PreToolUse";
	const after = event === "PostToolUse";
	if (!starting && !before && !after) return;
	if (!starting && (!input.session_id || !input.tool_use_id)) return;

	const directory = path.join(root, "build/run/editor-problems/baselines");
	const key = createHash("sha256").update(JSON.stringify([input.session_id, input.tool_use_id])).digest("hex");
	const baseline = path.join(directory, key + ".json");
	let previous;
	if (after) {
		try {
			previous = JSON.parse(fs.readFileSync(baseline, "utf8"));
		} catch (error) {
			if (error.code === "ENOENT") return;
			throw error;
		} finally {
			fs.rmSync(baseline, { force: true });
		}
	}

	let problems;
	try {
		problems = readProblems();
	} catch (error) {
		if (starting || after) emit(event, `Live VS Code Problems are unavailable. ${error.message} Use the relevant workspace CLI if diagnostics are needed.`);
		return;
	}

	if (before) {
		fs.mkdirSync(directory, { recursive: true });
		const cutoff = Date.now() - 24 * 60 * 60 * 1000;
		for (const entry of fs.readdirSync(directory, { withFileTypes: true })) {
			if (!entry.isFile() || !/^[a-f0-9]{64}\.json$/.test(entry.name)) continue;
			const file = path.join(directory, entry.name);
			try {
				if (fs.statSync(file).mtimeMs < cutoff) fs.rmSync(file, { force: true });
			} catch (error) {
				if (error.code !== "ENOENT") throw error;
			}
		}
		fs.writeFileSync(baseline, JSON.stringify(problems.map(signature)));
		return;
	}

	const counts = new Map();
	for (const item of previous ?? []) counts.set(item, (counts.get(item) ?? 0) + 1);
	const added = problems.filter(problem => {
		const key = signature(problem);
		const count = counts.get(key) ?? 0;
		if (count === 0) return true;
		counts.set(key, count - 1);
		return false;
	});
	const removed = [...counts.values()].reduce((sum, count) => sum + count, 0);
	if (after && added.length === 0 && removed === 0) return;
	const errors = problems.filter(problem => problem.severity === "error").length;
	const details = added.filter(problem => after || problem.severity === "error").slice(0, 8);
	const heading = after ? `VS Code Problems: ${added.length} added, ${removed} resolved.` : "VS Code Problems at session start.";
	emit(event, [
		`${heading} ${errors} errors, ${problems.length} total. Snapshot may lag a saved edit.`,
		...details.map(problem => `- ${JSON.stringify([problem.file, problem.line, problem.column, problem.severity, String(problem.message).slice(0, 250)])}`),
	].join("\n"));
}

try {
	main(JSON.parse(fs.readFileSync(0, "utf8")));
} catch (error) {
	console.error(`Template Problems hook: ${error.message}`);
}
