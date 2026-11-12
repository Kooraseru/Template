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
	assert.deepEqual(controller.jobs.publish.needs, ["build"]); assert.equal(controller.jobs.build.permissions.contents, "read"); assert.equal(controller.jobs.publish.permissions.contents, "write");
	for (const file of Object.values(files)) assert.ok(!file.includes('"inherit"'));
	const build = JSON.parse(files["build.yml"].slice(files["build.yml"].indexOf("{"))); assert.ok(build.on.workflow_call);
	for (const job of Object.values(build.jobs)) assert.equal(job.environment, undefined);
});
test("local Build omits Publish and every discovered Build component is rendered", t => {
	const files = execute(t, 'local B=require("@ci/bootstrap")\nlocal W=require("@ci/github/workflows/workflow")\nlocal J=require("@formats/json")\nprint(J.encode(W.Bundle(B.new("push"):BuildPlan(),string.rep("a",40),"ci-run-1-1","push")))', { ACT: "true", CI_OPERATION: "build" });
	assert.equal(files["publish.yml"], undefined); assert.equal(JSON.parse(files["pipeline.yml"]).jobs.publish, undefined);
});
test("hybrid CI keeps a required validation gate and separates publication credentials", () => {
	const workflow = fs.readFileSync(path.join(root, ".github/workflows/ci.yml"), "utf8").replace(/\r\n/g, "\n");
	assert.match(workflow, /^  build:\n    name: Build Project Components$/m);
	assert.match(workflow, /^  tests:\n    name: Execute Test Suites$/m);
	assert.match(workflow, /^  validate:\n    name: validate$/m);
	assert.match(workflow, /test "\$BUILD_RESULT" = success/);
	assert.match(workflow, /test "\$TEST_RESULT" = success/);
	assert.match(workflow, /^  publish-general:/m);
	assert.match(workflow, /^  publish-projects:/m);
	assert.match(workflow, /^  publish-rulesets:/m);
	assert.doesNotMatch(workflow, /^  bootstrap-environment:/m);
	assert.doesNotMatch(workflow, /^  bootstrap-oidc:/m);
});
test("optional administration components use their current skip policies", t => {
	const source = 'local S=require("@ci/bootstrap/outcomes/skipPolicy")\nlocal J=require("@formats/json")\nprint(J.encode({projects=S.Conclusion("work/projects/sync"),rulesets=S.Conclusion("governance/rulesets/sync"),default=S.Conclusion("source/build")}))';
	const results = execute(t, source);
	assert.deepEqual(results, { projects: "success", rulesets: "success", default: "neutral" });
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


test("fixed Publish jobs are separately gated and grant label/milestone access", () => {
	const workflow = fs.readFileSync(path.join(root, ".github/workflows/ci.yml"), "utf8").replace(/\r\n/g, "\n");
	assert.equal((workflow.match(/CI_STAGE_MODE: fixed/g) || []).length, 4);
	assert.match(workflow, /  publish-general:[\s\S]*?    permissions:\n      contents: write\n      issues: write/);
	assert.match(workflow, /  publish-projects:[\s\S]*?CI_CREDENTIAL_PROJECTS_TOKEN:/);
	assert.match(workflow, /  publish-rulesets:[\s\S]*?CI_CREDENTIAL_APP_PRIVATE_KEY:/);
	for (const name of ["publish-general", "publish-projects", "publish-rulesets"]) {
		assert.match(workflow, new RegExp("  " + name + ":[\\s\\S]*?    needs: validate"));
	}
});

test("example release and package policies never replace existing assets by default", () => {
	const release = JSON.parse(fs.readFileSync(path.join(root, ".github/config/publishing/releases/settings.json"), "utf8"));
	const packages = fs.readFileSync(path.join(root, ".github/config/publishing/packages/settings.toml"), "utf8");
	assert.equal(release.release.on_existing, "skip");
	assert.match(packages, /^on_existing = "skip"$/m);
});

test("fixed publication preserves legacy generated-branch protections and rehearses upload URLs", () => {
	const publication = fs.readFileSync(path.join(root, "ci/github/publication/init.luau"), "utf8");
	assert.match(publication, /local fixedStage = Process\.env\.CI_STAGE_MODE == "fixed"/);
	assert.match(publication, /if graphRun and not fixedStage then/);
	assert.match(publication, /or defaultBranch ~= "source"/);
	assert.match(publication, /local uploadOrigin = if Process\.env\.TEMPLATE_PUBLICATION_REHEARSAL == "1"/);
});


test("unimplemented native Pages and attestation integrations are disabled by default", () => {
	const targets = fs.readFileSync(path.join(root, ".github/config/targets.toml"), "utf8");
	const attestations = fs.readFileSync(path.join(root, ".github/config/publishing/attestations.toml"), "utf8");
	const execution = fs.readFileSync(path.join(root, ".github/config/ci/execution.toml"), "utf8");
	assert.match(targets, /^pages = false\b/m);
	assert.match(attestations, /^mode = "disabled"/m);
	assert.match(execution, /^"documentation\/pages\/publish" = "success"$/m);
	assert.match(execution, /^"distribution\/attestations\/publish" = "success"$/m);
});
