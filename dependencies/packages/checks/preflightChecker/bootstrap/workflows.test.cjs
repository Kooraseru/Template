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
test("authored routing preserves the required validation check", () => {
	const workflow = fs.readFileSync(path.join(root, ".github/workflows/ci.yml"), "utf8");
	assert.match(workflow, /^  resolve:\n    name: Resolve$/m);
	assert.match(workflow, /^  bootstrap-environment:\n    name: Bootstrap$/m);
	assert.match(workflow, /^  validate:\n    name: validate$/m);
	assert.match(workflow, /name: Require successful resolution/);
	assert.doesNotMatch(workflow, /^  validation:/m);
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


test("manual Build does not generate a Publish workflow or publication permissions", t => {
	const files = execute(t, 'local B=require("@ci/bootstrap")\nlocal W=require("@ci/github/workflows/workflow")\nlocal J=require("@formats/json")\nprint(J.encode(W.Bundle(B.new("workflow_dispatch"):BuildPlan(),string.rep("a",40),"ci-run-1-1","workflow_dispatch")))', { ACT: "", CI_OPERATION: "build" });
	assert.equal(files["publish.yml"], undefined);
	const controller = JSON.parse(files["pipeline.yml"]);
	assert.equal(controller.jobs.publish, undefined);
	assert.equal(controller.jobs.build.permissions.contents, "read");
});
