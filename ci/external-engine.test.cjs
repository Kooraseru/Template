"use strict";
// This test verifies that the external engine and trusted local publisher
// share an event policy without weakening either permission boundary.
const test = require("node:test");
const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");

const root = path.resolve(__dirname, "..");
const engine = JSON.parse(fs.readFileSync(path.join(root, "config/ci/operations.json"), "utf8"));
test("one canonical operation catalog owns component selection", () => {
  assert.equal(engine.version, 1);
  assert.equal(engine.componentRoot, ".github/components");
  assert.equal(fs.existsSync(path.join(root, "config/ci/engine.json")), false);
  assert.equal(fs.existsSync(path.join(root, ".github/config")), false);
  assert.equal(fs.existsSync(path.join(root, "ci/components")), false);
});
test("capability contracts declare an explicit setup prerequisite", () => {
  const rootPath=path.join(root,engine.componentRoot);
  const components=["setup","workflows","code-review","rules-audit","build-tests","template-updates"];
  for (const name of components) {
    const filename=path.join(rootPath,"quality",name,"component.json");
    const entry=JSON.parse(fs.readFileSync(filename,"utf8"));
    assert.equal(entry.boundary,"read",name);
    assert.deepEqual(entry.requires,name==="setup"?[]:["tools.workspace"],name);
    assert.equal(entry.command.length,2);
  }
});

test("Grouped callers share one pinned engine dependency reference", () => {
  const directory = path.join(root, ".github/workflows");
  const names = fs.readdirSync(directory).filter(name => /\.ya?ml$/.test(name) && !(process.env.ACT === "true" && name.startsWith("_act-"))).sort();
  const bootstrap = fs.readFileSync(path.join(directory, "bootstrap.yml"), "utf8");
  assert.match(bootstrap, /workflow_call:/);
  assert.doesNotMatch(bootstrap, /workflow_dispatch:|runs-on:/);
  assert.equal([...bootstrap.matchAll(/uses: Kooraseru-Hub\/CI-Engine\/\.github\/workflows\/bootstrap\.yml@[a-f0-9]{40}/g)].length, 1);
  for (const name of names.filter(name => name !== "bootstrap.yml")) {
    const workflow = fs.readFileSync(path.join(directory, name), "utf8");
    assert.match(workflow, /uses: \.\/\.github\/workflows\/bootstrap\.yml/);
    assert.doesNotMatch(workflow, /Kooraseru-Hub\/CI-Engine|runs-on:|secrets: inherit|workflow_call:/);
  }
  const lock = fs.readFileSync(path.join(directory, "actions.lock"), "utf8");
  for (const name of names) assert.ok(lock.includes(".github/workflows/" + name));
});
test("generated operations retain trusted adapters without hardcoded jobs in Template CI", () => {
  const ops = engine.operations;
  for(const name of ["build","publish"]) {
    const item=ops[name];
    assert.equal(item.mode,"generated");
    assert.equal(item.environment,"ci-bootstrap");
    assert.equal(item.plan,"build");
    assert.equal(item.branch,"default");
    assert.equal(item.execution.command[0],"node");
  }
  assert.equal(ops.build.publication,false);
  assert.equal(ops.publish.publication,true);
  assert.equal(ops.review.mode,"readonly");
});

test("source ruleset requires the actual external reusable workflow gate", () => {
  const source = JSON.parse(fs.readFileSync(path.join(root, "config/rulesets/source-gate.json"), "utf8"));
  const rule = source.rules.find(item => item.type === "required_status_checks");
  assert.ok(rule, "a required status checks rule must exist");
  assert.deepEqual(rule.parameters.required_status_checks, [
    { context: "CI Engine / engine / validate", integration_id: 15368 },
  ]);
});
