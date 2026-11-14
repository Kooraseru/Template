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

test("trusted workflow retains privileged bootstrap and external read-only engine", () => {
  const source=fs.readFileSync(path.join(root,".github/workflows/ci.yml"),"utf8");
  assert.match(source,/uses: Kooraseru-Hub\/CI-Engine@extraction\/pr43-contract-planner/);
  assert.match(source,/id-token: write/);
  assert.match(source,/CI_CREDENTIAL_BOOTSTRAP_TOKEN/);
  assert.match(source,/needs: \[resolve, checks, bootstrap\]/);
  assert.match(source,/actions\/upload-artifact@v7/);
  assert.doesNotMatch(source,/secrets: inherit/);
});
