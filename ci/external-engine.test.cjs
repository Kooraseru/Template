"use strict";
const test = require("node:test");
const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");
const root = path.resolve(__dirname, "..");
const configPath = path.join(root, ".github/config/ci/engine.json");
const external = fs.existsSync(configPath);

test("one stable, SHA-pinned external launcher with no embedded runtimes", { skip: !external }, () => {
  const workflow = fs.readFileSync(path.join(root, ".github/workflows/ci.yml"), "utf8");
  const jobSection = workflow.split(/\njobs:\s*\n/)[1];
  assert.ok(jobSection);
  const jobs = [...jobSection.matchAll(/^  ([\w-]+):$/gm)].map(match => match[1]);
  assert.deepEqual(jobs, ["bootstrap"]);
  assert.match(workflow, /uses: Kooraseru-Hub\/CI-Engine\/\.github\/workflows\/bootstrap\.yml@[a-f0-9]{40}/);
  assert.doesNotMatch(workflow, /setup-node|node ci\/|secrets\.|secrets: inherit|mise-action|workflow_call:/);
  assert.match(workflow, /contents: read/);
});

test("event routing is data-owned and default-branch build policy is explicit", { skip: !external }, () => {
  const config = JSON.parse(fs.readFileSync(configPath, "utf8"));
  assert.equal(config.version, 1);
  assert.equal(config.triggers.pull_request, "review");
  assert.equal(config.triggers.push, "build");
  assert.equal(config.operations.build.branch, "default");
  assert.equal(config.operations.build.mode, "generated");
  assert.equal(config.operations.review.mode, "readonly");
  assert.ok(config.componentRoot.startsWith(".github/config/ci/"));
});

test("component capabilities resolve without language-specific engine conditions", { skip: !external }, () => {
  const config = JSON.parse(fs.readFileSync(configPath, "utf8"));
  const directory = path.join(root, config.componentRoot);
  const names = ["quality/setup", "quality/code-review", "quality/rules-audit", "quality/test-suites"];
  const components = Object.fromEntries(names.map(name => [
    name, JSON.parse(fs.readFileSync(path.join(directory, name, "component.json"), "utf8")),
  ]));
  const provider = new Map();
  for (const [name, component] of Object.entries(components)) {
    assert.equal(component.boundary, "read");
    assert.ok(Array.isArray(component.command) && component.command.length > 0);
    assert.ok(component.command.every(value => typeof value === "string" && value.length > 0));
    for (const capability of component.provides) {
      assert.ok(!provider.has(capability));
      provider.set(capability, name);
    }
  }
  assert.equal(provider.get("tools.workspace"), "quality/setup");
  for (const name of names.slice(1)) {
    assert.deepEqual(components[name].requires, ["tools.workspace"]);
  }
});
