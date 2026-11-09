"use strict";

const assert = require("node:assert/strict");
const fs = require("node:fs");
const { execFile, spawnSync } = require("node:child_process");

const remote = "/tmp/template-preflight.git";
const labelTask = "work/labels/sync";
const branchTask = "governance/branches/publish";
const safeEnv = { PATH: process.env.PATH, HOME: "/tmp", GIT_CONFIG_NOSYSTEM: "1" };

function run(argv, env = safeEnv) {
	const result = spawnSync(argv[0], argv.slice(1), {
		env, encoding: "utf8", timeout: 45_000, maxBuffer: 1024 * 1024,
	});
	if (result.error) throw new Error("Required command unavailable, timed out, or exceeded its output limit.");
	return result;
}

function git(...args) {
	const result = run(["git", ...args]);
	assert.equal(result.status, 0, "Local Git fixture operation failed.");
	return result.stdout.trim();
}

function prepareBranches(branches, scenario) {
	git("init", "--bare", remote);
	const parents = new Map();
	if (scenario === "update") {
		const tree = git("--git-dir", remote, "mktree");
		const parent = git("--git-dir", remote, "-c", "user.name=Fixture", "-c",
			"user.email=fixture@example.invalid", "commit-tree", tree, "-m", "Seed");
		for (const branch of branches) {
			git("--git-dir", remote, "update-ref", "refs/heads/" + branch, parent);
			parents.set(branch, parent);
		}
	}
	if (scenario === "reject") {
		fs.writeFileSync(remote + "/hooks/pre-receive", "#!/bin/sh\necho 'protected branch' >&2\nexit 1\n", { mode: 0o755 });
	}
	return parents;
}

function assertBranches(branches, parents) {
	assert.ok(branches.length, "No branch outputs were configured.");
	for (const branch of branches) {
		const ref = "refs/heads/" + branch;
		const tree = git("--git-dir", remote, "rev-parse", ref + "^{tree}");
		assert.equal(tree, git("-C", "build/github/branches/" + branch, "write-tree"));
		assert.ok(git("--git-dir", remote, "ls-tree", "-r", "--name-only", ref));
		if (parents.has(branch)) assert.equal(git("--git-dir", remote, "rev-parse", ref + "^"), parents.get(branch));
	}
}

async function main() {
	const { steps, scenario } = JSON.parse(fs.readFileSync(0, "utf8"));
	const target = steps.at(-1).id;
	const supported = target === labelTask ? ["create", "active", "archived", "malformed", "http-error"] : ["create", "update", "reject"];
	assert.ok(supported.includes(scenario), "Unsupported rehearsal scenario.");
	const config = fs.readFileSync(".vscode/config/luau/.luaurc", "utf8");
	fs.writeFileSync(".luaurc", config.replace(/("workspace"\s*:\s*)"\.\.\/\.\.\/\.\."/u, '$1"."'));
	fs.mkdirSync("build/dependencies", { recursive: true });
	fs.symlinkSync("/tools/build/dependencies/types", "build/dependencies/types", "dir");
	fs.symlinkSync("/tools/build/dependencies/npm", "build/dependencies/npm", "dir");
	const { startMock } = require("./githubMock.cjs");

	const loaded = run(["lute", "run", "dependencies/packages/checks/preflightChecker/bootstrap/inputs.luau"]);
	assert.equal(loaded.status, 0, loaded.stderr);
	const inputs = JSON.parse(loaded.stdout);
	const env = {
		...safeEnv, GITHUB_ACTIONS: "true", GITHUB_REPOSITORY: inputs.repository,
		GITHUB_REF: "refs/heads/source", CI_EVENT: "push", GH_TOKEN: "rehearsal-token",
		TEMPLATE_PUBLICATION_REHEARSAL: "1",
	};
	const mock = await startMock(inputs, target === labelTask ? scenario : "active");
	const outcomes = [];
	try {
		const parents = target === branchTask ? prepareBranches(inputs.branches, scenario) : new Map();
		for (const step of steps) {
			const started = Date.now();
			const outcome = { id: step.id, status: "passed", durationMs: 0 };
			try {
				if (step.id === "source/build" && target === branchTask) {
					outcome.status = "skipped";
					outcome.reason = "Source compilation requires Docker builds. Its artifacts are separate from the generated branch tree exercised here.";
				} else if (step.needs.some(id => outcomes.some(previous => previous.id === id &&
					previous.status !== "passed" && !(id === "source/build" && previous.status === "skipped" && step.id === branchTask)))) {
					outcome.status = "skipped";
					outcome.reason = "A required predecessor did not pass.";
				} else if (![labelTask, branchTask, "governance/branches/build"].includes(step.id)) {
					outcome.status = "skipped";
					outcome.reason = "No offline fixture is configured for this task.";
				} else {
					const [executable, ...args] = step.command;
					const result = await new Promise(resolve => {
						execFile(executable, args, { env, timeout: 45_000, maxBuffer: 1024 * 1024 },
							(error, _stdout, stderr) => resolve({ status: error ? error.code ?? "interrupted" : 0, stderr }));
					});
					assert.equal(mock.violations.length, 0, mock.violations[0]);
					if (step.id === labelTask || step.id === branchTask) {
						outcome.coverage = "substitute";
						outcome.service = step.id === labelTask ? "GitHub REST" : "GitHub REST and local Git";
						outcome.operations = [...new Set(mock.operations)];
						outcome.writeAcceptance = "unverified";
					}
					if (result.status === 78) {
						if (step.id !== labelTask || scenario !== "active") throw new Error("Task skipped without proving the expected operation.");
					} else if (result.status !== 0) {
						const detail = result.stderr.split(/\r?\n/).map(line => line.match(
							/^(?:Branch publication Git push refs\/heads\/[\w-]+ failed with exit code \d+:.*|Configured label .* is archived;.*|GitHub returned a non-JSON response for .* \(HTTP \d+\)|Read label .*: GitHub returned HTTP 503)/))
							.find(Boolean)?.[0];
						throw new Error(detail || "Publication command failed (exit " + result.status + ").");
					}
					if (step.id === labelTask) mock.assertLabels();
					if (step.id === branchTask) {
						assertBranches(inputs.branches, parents);
						outcome.operations.push("update local Git refs");
					}
				}
			} catch (error) {
				outcome.status = "failed";
				outcome.reason = error instanceof assert.AssertionError ? "Offline request or output assertion failed." : error.message;
			}
			outcome.durationMs = Date.now() - started;
			outcomes.push(outcome);
		}
	} finally {
		mock.server.close();
	}
	process.stdout.write(JSON.stringify(outcomes));
}

main().catch(error => {
	console.error(error.message);
	process.exitCode = 1;
});
