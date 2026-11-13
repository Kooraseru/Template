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
	for (const file of Object.values(files)) assert.ok(!file.includes('"inherit"'));
	const build = JSON.parse(files["build.yml"].slice(files["build.yml"].indexOf("{"))); assert.ok(build.on.workflow_call);
	for (const job of Object.values(build.jobs)) assert.equal(job.environment, undefined);
});
test("local Build omits Publish and every discovered Build component is rendered", t => {
	const files = execute(t, 'local B=require("@ci/bootstrap")\nlocal W=require("@ci/github/workflows/workflow")\nlocal J=require("@formats/json")\nprint(J.encode(W.Bundle(B.new("push"):BuildPlan(),string.rep("a",40),"ci-run-1-1","push")))', { ACT: "true", CI_OPERATION: "build" });
	assert.equal(files["publish.yml"], undefined); assert.equal(JSON.parse(files["pipeline.yml"]).jobs.publish, undefined);
});
test("only one permanent workflow delegates operations to JSON", () => {
	const directory = path.join(root, ".github/workflows");
	const authored = fs.readdirSync(directory).filter(name => /\.ya?ml$/.test(name)).sort();
	assert.deepEqual(authored, ["ci.yml"]);
	const workflow = fs.readFileSync(path.join(directory, "ci.yml"), "utf8").replace(/\r\n/g, "\n");
	for (const job of ["setup", "resolve", "authorize", "generate", "execute", "collect", "cleanup", "validate"]) {
		assert.match(workflow, new RegExp("^  " + job + ":$", "m"));
	}
	for (const job of ["review", "audit", "bootstrap", "build", "tests", "publish"]) {
		assert.doesNotMatch(workflow, new RegExp("^  " + job + ":$", "m"));
	}
	for (const command of ["resolve", "authorize", "generate", "run", "collect", "cleanup", "validate"]) {
		assert.match(workflow, new RegExp("node ci/controller/stages\\.cjs " + command));
	}
	assert.doesNotMatch(workflow, /^  publish-(general|projects|rulesets):$/m);
	assert.doesNotMatch(workflow, /secrets\.CI_TOKEN|secrets\.CI_APP_PRIVATE_KEY/);
	const config = require(path.join(root, "dependencies/packages/core/dependencyLoader/vendor/toml.cjs")).parse(fs.readFileSync(path.join(root, ".github/config/ci/settings.toml"), "utf8"));
	assert.equal(config.triggers.pull_request, "review");
	assert.equal(config.checks["rules-audit"].group, "audit");
	assert.ok(config.operations.review.checks.includes("rules-audit"));
	assert.equal(config.triggers.push, "publish");
});
test("optional administration components use their current skip policies", t => {
	const source = 'local S=require("@ci/bootstrap/outcomes/skipPolicy")\nlocal J=require("@formats/json")\nprint(J.encode({projects=S.Conclusion("work/projects/sync"),rulesets=S.Conclusion("governance/rulesets/sync"),default=S.Conclusion("source/build")}))';
	const results = execute(t, source);
	assert.deepEqual(results, { projects: "success", rulesets: "success", default: "neutral" });
});
test("component contract rejects missing phases and privileged Build", t => {
	const result = execute(t, 'local C=require("@ci/bootstrap/contracts/contract")\nlocal J=require("@formats/json")\nlocal a=pcall(C.new,"example","x","fixture",{provides={"example"}})\nlocal b=pcall(C.new,"example","x","fixture",{provides={"example"},phase="build",boundary="privileged",events={"push"}})\nprint(J.encode({a=a,b=b}))'); assert.equal(result.a, false); assert.equal(result.b, false);
});

test("read-only command components require no Luau wrapper and reject privileged commands", t => {
	const source = 'local B=require("@ci/bootstrap")\nlocal C=require("@ci/bootstrap/contracts/contract")\nlocal J=require("@formats/json")\nlocal entries={}\nfor _,task in B.Plan("push") do if task.identity == "quality/code-review" or task.identity == "quality/rules-audit" then entries[task.identity]=task.entry end end\nlocal ok=pcall(C.new,"other/test","x","fixture",{phase="publish",boundary="privileged",provides={"test"},events={"push"},command={"sh","-c","echo unsafe"}})\nprint(J.encode({entries=entries,privilegedAccepted=ok}))';
	const result = execute(t, source);
	assert.deepEqual(result.entries, {
		"quality/code-review": "ci/components/quality/code-review/component.toml",
		"quality/rules-audit": "ci/components/quality/rules-audit/component.toml",
	});
	assert.equal(result.privilegedAccepted, false);
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
});
test("unimplemented native Pages and attestation integrations are disabled by default", () => {
	const targets = fs.readFileSync(path.join(root, ".github/config/targets.toml"), "utf8");
	const attestations = fs.readFileSync(path.join(root, ".github/config/publishing/attestations.toml"), "utf8");
	const execution = fs.readFileSync(path.join(root, ".github/config/ci/settings.toml"), "utf8");
	assert.match(targets, /^pages = false\b/m);
	assert.match(attestations, /^mode = "disabled"/m);
	assert.match(execution, /^"documentation\/pages\/publish" = "success"$/m);
	assert.match(execution, /^"distribution\/attestations\/publish" = "success"$/m);
});

test("linear compiler generates selected components without a second cleanup owner", t => {
	const directory = fs.mkdtempSync(path.join(root, "build/component-selection-"));
	t.after(() => fs.rmSync(directory, { recursive: true, force: true }));
	const result = spawnSync(lute, ["run", "ci/bootstrap/generateWorkflows.luau", directory], {
		cwd: root, encoding: "utf8", timeout: 35000, windowsHide: true,
		env: {
			...process.env, GITHUB_SHA: "a".repeat(40), CI_GENERATED_BRANCH: "ci/run-fixture-1",
			CI_EVENT: "push", CI_OPERATION: "build", CI_PUBLICATION_ENABLED: "false",
			CI_SELECTED_COMPONENTS: JSON.stringify(["quality/code-review", "quality/rules-audit"]),
		},
	});
	assert.ifError(result.error);
	assert.equal(result.status, 0, result.stdout + result.stderr);
	const pipeline = JSON.parse(fs.readFileSync(path.join(directory, "pipeline.yml"), "utf8"));
	assert.equal(pipeline.jobs.cleanup, undefined, "Controller cleanup must be the sole branch owner");
	assert.equal(pipeline.jobs.publish, undefined, "Selection must not publish without authorization");
	assert.equal(pipeline.jobs.build.name, "Build");
	const build = JSON.parse(fs.readFileSync(path.join(directory, "build.yml"), "utf8").replace(/^#.*\n/, ""));
	const components = Object.values(build.jobs).filter(job => job.name?.startsWith("quality/")).map(job => job.name).sort();
	assert.deepEqual(components, ["quality/code-review", "quality/rules-audit"]);
});
