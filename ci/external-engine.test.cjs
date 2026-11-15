"use strict";
// This test verifies that the external engine and trusted local publisher
// share an event policy without weakening either permission boundary.
const test = require("node:test");
const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");

const root = path.resolve(__dirname, "..");
const engine = JSON.parse(fs.readFileSync(path.join(root, ".github/config/ci/engine.json"), "utf8"));
const routing = JSON.parse(fs.readFileSync(path.join(root, ".github/config/ci/operations.json"), "utf8"));

test("external engine routes stay synchronized with canonical CI operations", () => {
  assert.equal(engine.version, 1);
  for(const [event, operation] of Object.entries(routing.triggers)) {
    assert.equal(engine.triggers[event], operation);
    assert.equal(engine.operations[operation].mode, routing.operations[operation].mode);
  }
  for(const [name, operation] of Object.entries(routing.operations)) {
    assert.deepEqual([...(engine.operations[name]?.events||[])].sort(), [...operation.events].sort(), name+" event mismatch");
    assert.equal(engine.operations[name]?.mode,operation.mode,name+" mode mismatch");
  }
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

test("Template is only a caller; job lifecycle and authorization belong to the reusable engine", () => {
  const source=fs.readFileSync(path.join(root,".github/workflows/ci.yml"),"utf8");
  assert.match(source,/uses: Kooraseru-Hub\/CI-Engine\/\.github\/workflows\/bootstrap\.yml@[a-f0-9]{40}/);
  assert.match(source,/id-token: write/);
  assert.match(source,/app_private_key: /);
  assert.match(source,/bootstrap_token: /);
  assert.match(source,/secrets\.CI_TOKEN/);
  assert.doesNotMatch(source,/secrets: inherit/);
  const section = source.split(/\njobs:\s*\n/)[1];
  assert.deepEqual([...section.matchAll(/^  ([\w-]+):$/gm)].map(x=>x[1]),["ci"]);
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
  const source = JSON.parse(fs.readFileSync(path.join(root, ".github/config/rulesets/source-gate.json"), "utf8"));
  const rule = source.rules.find(item => item.type === "required_status_checks");
  assert.ok(rule, "a required status checks rule must exist");
  assert.deepEqual(rule.parameters.required_status_checks, [
    { context: "CI Engine / validate", integration_id: 15368 },
  ]);
});
