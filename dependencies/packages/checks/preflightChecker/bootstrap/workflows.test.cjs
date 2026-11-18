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
function nativePlan(t) {
  const directory=fs.mkdtempSync(path.join(root,"build/delivery-test-"));
  t.after(()=>fs.rmSync(directory,{recursive:true,force:true}));
  const file=path.join(directory,"plan.json");
  const script=path.join(root,"dependencies/managed/packages/ci-engine/src/native/bootstrap/deliveryPlan.luau");
  const result=spawnSync(lute,["run",script],{cwd:root,encoding:"utf8",timeout:30000,
    env:{...process.env,CI_DELIVERY_PLAN_FILE:file}});
  assert.ifError(result.error);assert.equal(result.status,0,result.stdout+result.stderr);
  return JSON.parse(fs.readFileSync(file,"utf8"));
}
test("native delivery plan covers each real publication component with its own lane",t=>{
  const plan=nativePlan(t);
  const tasks=execute(t,'local B=require("@ci/bootstrap")\nlocal J=require("@formats/json")\nprint(J.encode(B.Plan("push")))');
  assert.deepEqual(plan.jobs.map(job=>job.id).sort(),tasks.filter(task=>task.phase==="publish").map(task=>task.identity).sort());
  const get=id=>plan.jobs.find(job=>job.id===id);
  assert.equal(get("work/labels/sync").lane,"issues");
  assert.equal(get("documentation/pages/publish").lane,"pages");
  assert.equal(get("documentation/pages/publish").pages_path,"build/github/pages");
  assert.equal(get("work/projects/sync").environment,"ci-projects");
  assert.deepEqual(get("work/projects/sync").bindings,[{role:"CI_CREDENTIAL_PROJECTS_TOKEN",source:"secret",name:"CI_TOKEN"}]);
  assert.equal(get("governance/rulesets/sync").environment,"ci-rulesets");
  assert.equal(get("governance/rulesets/sync").lane,"credential");
  assert.equal(plan.artifact,plan.destination);
  assert.match(plan.artifact,/^build\/run\/[^/]+\/transport\/bundles$/);
  const {normalize}=require("../../../../../dependencies/managed/packages/ci-engine/src/adapters/github/delivery.cjs");
  assert.equal(normalize(plan).jobs.length,plan.jobs.length);
});
test("same-run delivery jobs cannot publish before Build and native Tests pass",()=>{
  const file=fs.readFileSync(path.join(root,"dependencies/managed/packages/ci-engine/.github/workflows/bootstrap.yml"),"utf8");
  for(const lane of ["contents","issues","credential","pages","external"]){
    const start=file.indexOf("\n  publish_"+lane+":");
    assert.ok(start>=0);
    const part=file.slice(start).split(/\n  [a-z_]+:\n/)[0];
    // Read the full job independently of matrix cardinality.
    const section=file.slice(start+1).split(/\n  [a-z_]+:\n/)[0];
    assert.match(section,/needs: \[resolve, plan, authorize, execute, test\]/);
    assert.match(section,/needs\.resolve\.outputs\.trusted == 'true'/);
    assert.match(section,/inputs\.publish/);
    assert.match(section,/needs\.execute\.result == 'success'/);
    assert.match(section,/needs\.test\.result == 'success'/);
    assert.match(section,/name: ci-delivery-input/);
    if(lane!=="pages")assert.doesNotMatch(section,/id-token: write|pages: write/);
    if(lane!=="contents")assert.doesNotMatch(section,/contents: write/);
    if(lane!=="issues")assert.doesNotMatch(section,/issues: write/);
  }
  assert.doesNotMatch(file,/Execute trusted generated adapter|CI_COMPONENT_CREDENTIALS|secrets: inherit/);
});
test("authored events dispatch independently from the pinned engine", () => {
  const directory=path.join(root,".github/workflows");
  const bootstrap=fs.readFileSync(path.join(directory,"bootstrap.yml"),"utf8");
  assert.match(bootstrap,/uses: Kooraseru-Hub\/CI-Engine\/\.github\/workflows\/bootstrap\.yml@[a-f0-9]{40}/);
  assert.match(bootstrap,/repository_dispatch:/);
  for(const file of ["push","pull","manual","remote"]){
    const workflow=fs.readFileSync(path.join(directory,file+".yml"),"utf8");
    assert.match(workflow,/ci-request/);
    assert.doesNotMatch(workflow,/uses: .*bootstrap\.yml|secrets: inherit/);
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


test("explicit Build never declares a delivery planner",()=>{
  const operations=JSON.parse(fs.readFileSync(path.join(root,"config/ci/operations.json"),"utf8")).operations;
  assert.equal(operations.build.mode,"readonly");
  assert.equal(operations.build.delivery,undefined);
  assert.equal(operations.publish.mode,"staged");
  assert.equal(operations.publish.publication,true);
});
test("example release and package policies never replace existing assets by default", () => {
	const release = JSON.parse(fs.readFileSync(path.join(root, "config/publishing/releases/settings.json"), "utf8"));
	const packages = fs.readFileSync(path.join(root, "config/publishing/packages/settings.toml"), "utf8");
	assert.equal(release.release.on_existing, "skip");
	assert.match(packages, /^on_existing = "skip"$/m);
});

test("publication requires admitted same-run trusted source and retains loopback uploads",()=>{
  const publication=fs.readFileSync(path.join(root,"dependencies/managed/packages/ci-engine/src/native/github/publication/init.luau"),"utf8");
  assert.match(publication,/Process\.env\.CI_GRAPH_RUN ~= "true"/);
  assert.match(publication,/Process\.env\.CI_PHASE ~= "publish"/);
  assert.match(publication,/Process\.env\.CI_ORIGIN_TRUSTED ~= "true"/);
  assert.match(publication,/Process\.env\.CI_PUBLICATION_ENABLED ~= "true"/);
  assert.match(publication,/source ~= Process\.env\.GITHUB_SHA/);
  assert.doesNotMatch(publication,/CI_RUN_BRANCH|CI_STAGE_MODE|fixedStage/);
  assert.match(publication,/local uploadOrigin = if Process\.env\.TEMPLATE_PUBLICATION_REHEARSAL == "1"/);
  assert.equal(fs.existsSync(path.join(root,"dependencies/managed/packages/ci-engine/src/native/github/resources/branches/branchRun.luau")),false);
});
test("trusted Pages publication is enabled while attestation signing remains disabled", () => {
	const targets = fs.readFileSync(path.join(root, "config/targets.toml"), "utf8");
	const attestations = fs.readFileSync(path.join(root, "config/publishing/attestations.toml"), "utf8");
	const execution = fs.readFileSync(path.join(root, "config/ci/execution.toml"), "utf8");
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
