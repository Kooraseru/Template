"use strict";
const test = require("node:test"), assert = require("node:assert/strict");
const fs = require("node:fs"), path = require("node:path");
const { spawnSync } = require("node:child_process");
const root = path.resolve(__dirname, "../../../../..");
const lute = path.join(root, "dependencies/managed/bin/lute", process.platform === "win32" ? "lute.exe" : "lute");
function execute(t, source, env = {}) {
	fs.mkdirSync(path.join(root, "build"), { recursive: true });
	const temporary = fs.mkdtempSync(path.join(root, "build/workflow-test-")); t.after(() => fs.rmSync(temporary, { recursive: true, force: true }));
	const file = path.join(temporary, "test.luau"); fs.writeFileSync(file, source);
	const result = spawnSync(lute, ["run", file], { cwd: root, encoding: "utf8", timeout: 20000, windowsHide: true, env: { ...process.env, ...env } }); assert.ifError(result.error); assert.equal(result.status, 0, result.stdout + result.stderr); return JSON.parse(result.stdout);
}
test("generated hosted stages enforce Build before Publish and read-only Validation", t => {
	const source = 'local B = require("@ci/bootstrap")\nlocal W = require("@ci/github/workflows/workflow")\nlocal J = require("@formats/json")\nprint(J.encode(W.Bundle(B.new("push"):BuildPlan(), string.rep("a",40), "ci-run-1-1", "push")))';
	const files = execute(t, source, { ACT: "", CI_OPERATION: "build" }); const controller = JSON.parse(files["pipeline.yml"]);
	assert.equal(controller.name, "Pipeline");
	assert.deepEqual(controller.jobs.publish.needs, ["build", "tests"]); assert.deepEqual(controller.jobs.tests.needs, ["build"]); assert.equal(controller.jobs.build.permissions.contents, "read"); assert.equal(controller.jobs.publish.permissions.contents, "write");
	// A reusable workflow cannot elevate the caller's GitHub token scope.
	// Validate all generated jobs so a new component cannot silently cause
	// a zero-job GitHub Actions startup_failure.
	const called = JSON.parse(files["publish.yml"].slice(files["publish.yml"].indexOf("{")));
	const allowed = controller.jobs.publish.permissions;
	for (const [name, job] of Object.entries(called.jobs)) {
		for (const [permission, access] of Object.entries(job.permissions || {})) {
			if (access === "write") assert.equal(allowed[permission], "write", name + ": " + permission);
			else assert.ok(["read", "write"].includes(allowed[permission]), name + ": " + permission);
		}
	}
	assert.equal(controller.jobs.publish.permissions.pages, "write");
	for (const file of Object.values(files)) assert.ok(!file.includes('"inherit"'));
	const build = JSON.parse(files["build.yml"].slice(files["build.yml"].indexOf("{"))); assert.ok(build.on.workflow_call);
	for (const job of Object.values(build.jobs)) assert.equal(job.environment, undefined);
});
test("local Build omits Publish and every discovered Build component is rendered", t => {
	const files = execute(t, 'local B=require("@ci/bootstrap")\nlocal W=require("@ci/github/workflows/workflow")\nlocal J=require("@formats/json")\nprint(J.encode(W.Bundle(B.new("push"):BuildPlan(),string.rep("a",40),"ci-run-1-1","push")))', { ACT: "true", CI_OPERATION: "build" });
	assert.equal(files["publish.yml"], undefined); assert.equal(JSON.parse(files["pipeline.yml"]).jobs.publish, undefined);
});
test("authored event workflows delegate directly to one external engine", () => {
  const directory = path.join(root, ".github/workflows");
  const authored = fs.readdirSync(directory).filter(name => /\.ya?ml$/.test(name)).sort();
  assert.deepEqual(authored, ["manual.yml","pull.yml","push.yml","remote.yml"]);
  for (const file of authored) {
    const workflow = fs.readFileSync(path.join(directory, file), "utf8");
    assert.match(workflow, /uses: Kooraseru-Hub\/CI-Engine\/\.github\/workflows\/bootstrap\.yml@[a-f0-9]{40}/);
    assert.doesNotMatch(workflow, /runs-on:|secrets: inherit|workflow_call:/);
  }
});
test("optional administration components use their current skip policies", t => {
	const source = 'local S=require("@ci/bootstrap/outcomes/skipPolicy")\nlocal J=require("@formats/json")\nprint(J.encode({projects=S.Conclusion("work/projects/sync"),rulesets=S.Conclusion("governance/rulesets/sync"),releases=S.Conclusion("distribution/releases/publish"),milestones=S.Conclusion("work/milestones/sync"),default=S.Conclusion("source/build")}))';
	const results = execute(t, source);
	assert.deepEqual(results, { projects: "success", rulesets: "success", default: "neutral", releases: "success", milestones: "success" });
});
test("component contract rejects missing phases and privileged Build", t => {
	const result = execute(t, 'local C=require("@ci/bootstrap/contracts/contract")\nlocal J=require("@formats/json")\nlocal a=pcall(C.new,"example","x","fixture",{provides={"example"}})\nlocal b=pcall(C.new,"example","x","fixture",{provides={"example"},phase="build",boundary="privileged",events={"push"}})\nprint(J.encode({a=a,b=b}))'); assert.equal(result.a, false); assert.equal(result.b, false);
});

test("Build dependencies on Publish are rejected before rendering", t => {
	const result = execute(t, 'local C=require("@ci/bootstrap/contracts/contract")\nlocal P=require("@ci/bootstrap/planning")\nlocal J=require("@formats/json")\nlocal a=C.new("prepare","x","fixture",{phase="build",provides={"prepared"},requires={"published"},events={"push"}})\nlocal b=C.new("send","x","fixture",{phase="publish",boundary="privileged",provides={"published"},events={"push"}})\nlocal ok=pcall(function() P.new():Resolve({a,b},"push") end)\nprint(J.encode({ok=ok}))'); assert.equal(result.ok, false);
});


test("legacy generated Build refuses to schedule Publish on manual dispatch", t => {
	const result = execute(t, 'local B=require("@ci/bootstrap")\nlocal W=require("@ci/github/workflows/workflow")\nlocal J=require("@formats/json")\nprint(J.encode({files=W.Bundle(B.new("workflow_dispatch"):BuildPlan(),string.rep("a",40),"ci-run-1-1","workflow_dispatch"),group=type(W.ComponentEnvironment)}))', { ACT: "", CI_OPERATION: "build" });
	assert.equal(result.group, "function");
	assert.equal(result.files["publish.yml"], undefined);
	assert.equal(JSON.parse(result.files["pipeline.yml"]).jobs.publish, undefined);
});


test("generated graph binds credential environments and isolates publication", t => {
	const code = 'local B=require("@ci/bootstrap")\nlocal W=require("@ci/github/workflows/workflow")\nlocal J=require("@formats/json")\nprint(J.encode(W.Bundle(B.new("push"):BuildPlan(),string.rep("a",40),"run/publish-1-1","push")))';
	const enabled = execute(t, code, { ACT: "", CI_OPERATION: "build", CI_PUBLICATION_ENABLED: "true", CI_EXECUTION_PREFIX: "run/publish-" });
	assert.ok(enabled["publish.yml"]);
	const compiled = JSON.parse(enabled["publish.yml"].slice(enabled["publish.yml"].indexOf("{")));
	assert.ok(compiled.on.workflow_call);
	const jobs = Object.values(compiled.jobs);
	assert.ok(jobs.some(job => job.environment?.name === "ci-projects"));
	assert.ok(jobs.some(job => job.environment?.name === "ci-rulesets"));
	assert.ok(jobs.some(job => job.permissions?.actions === "read"));
	assert.ok(!enabled["publish.yml"].includes("actions/download-artifact@v8"));
	const disabled = execute(t, code, { ACT: "", CI_OPERATION: "build", CI_PUBLICATION_ENABLED: "false", CI_EXECUTION_PREFIX: "run/build-" });
	assert.equal(disabled["publish.yml"], undefined);
});
test("example release and package policies never replace existing assets by default", () => {
	const release = JSON.parse(fs.readFileSync(path.join(root, ".github/config/publishing/releases/settings.json"), "utf8"));
	const packages = fs.readFileSync(path.join(root, ".github/config/publishing/packages/settings.toml"), "utf8");
	assert.equal(release.release.on_existing, "skip");
	assert.match(packages, /^on_existing = "skip"$/m);
});

test("generated publication retains branch checks and rehearses release uploads", () => {
	const publication = fs.readFileSync(path.join(root, "ci/github/publication/init.luau"), "utf8");
	assert.match(publication, /if graphRun and not fixedStage then/);
	assert.match(publication, /configuration\.branchPrefix/);
	assert.match(publication, /local uploadOrigin = if Process\.env\.TEMPLATE_PUBLICATION_REHEARSAL == "1"/);
	const runtime = fs.readFileSync(path.join(root, "ci/github/resources/branches/branchRun.luau"), "utf8");
	assert.match(runtime, /pcall\(waitForPipeline, repository, branch, revision, true\)/);
	assert.match(runtime, /record\("failed", tostring\(problem\)\)/);
	assert.match(runtime, /Temporary CI branch moved after this run started/);
	assert.match(runtime, /Fs\.remove\(permanent\)/);
	assert.match(runtime, /pcall\(waitForPipeline, repository, branch, revision, true\)/);
	assert.match(runtime, /pcall\(removeOwnedRun, configuration, repository, branch, revision, runId, attempt, fresh\.token\)/);
	assert.match(runtime, /decoded\.object\.sha ~= revision/);
	assert.match(runtime, /Generated CI succeeded but branch cleanup failed/);
	assert.match(runtime, /git\/matching-refs\/heads\//);
	assert.match(runtime, /parentRun\.status ~= "completed"/);
	assert.match(runtime, /generated\.message ~= "CI execution graph for " \.\. originSha/);
	assert.match(runtime, /original\.sha ~= originSha/);
	assert.match(runtime, /gsub\("\(\[\^%w_\.\/~\-\]\)"/);
});
test("trusted Pages publication is enabled while attestation signing remains disabled", () => {
	const targets = fs.readFileSync(path.join(root, ".github/config/targets.toml"), "utf8");
	const attestations = fs.readFileSync(path.join(root, ".github/config/publishing/attestations.toml"), "utf8");
	const execution = fs.readFileSync(path.join(root, ".github/config/ci/execution.toml"), "utf8");
	assert.match(targets, /^pages = true\b/m);
  assert.match(targets, /^branches = false\b/m);
  assert.ok(!targets.includes("pages-state"));
  assert.ok(targets.includes("cloudflare_project ="));
	assert.match(targets, /^releases = false\b/m);
	assert.match(targets, /^milestones = false\b/m);
	assert.match(execution, /^"distribution\/releases\/publish" = "success"$/m);
	assert.match(execution, /^"work\/milestones\/sync" = "success"$/m);
	assert.match(attestations, /^mode = "disabled"/m);
	assert.match(execution, /^"documentation\/pages\/publish" = "success"$/m);
	assert.match(execution, /^"distribution\/attestations\/publish" = "success"$/m);
});
