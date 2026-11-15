"use strict";
const test=require("node:test");
const assert=require("node:assert/strict");
const {hosts,render,validate}=require("./preview.cjs");
const SHA="a".repeat(40), BRANCH="ci/run-pr-46-abcdef0123";
test("generated PR workflow uses discovered real host contracts",()=>{
  assert.deepEqual(hosts(),["windows-amd","windows-arm64","windows-intel"]);
  const files=render(BRANCH,SHA);
  assert.deepEqual(Object.keys(files).sort(),["build.yml","distribution.yml","pipeline.yml","plan.yml","quality.yml","tests.yml"]);
  for(const host of hosts()) assert.match(files["build.yml"],new RegExp("target: "+host));
  assert.match(files["build.yml"],/strategy:\n      fail-fast: false\n      matrix:/);
  assert.match(files["build.yml"],/name: Pages/);
  assert.match(files["build.yml"],/name: Branches/);
  assert.match(files["build.yml"],/--component documentation\/pages\/build/);
  assert.match(files["build.yml"],/--component governance\/branches\/build/);
  assert.doesNotMatch(files["build.yml"],/--component .*\/publish/);
  assert.match(files["pipeline.yml"],/uses: .\/.github\/workflows\/build.yml/);
  assert.match(files["quality.yml"],/name: Review/);
  assert.match(files["tests.yml"],/name: Universal/);
  assert.match(files["tests.yml"],/name: .*matrix\.label/);
  assert.match(files["tests.yml"],/runner: windows-11-arm/);
  assert.match(files["tests.yml"],/runner: windows-latest/);
  assert.match(files["tests.yml"],/actions\/download-artifact@v8/);
  assert.match(files["tests.yml"],/Host-specific output mismatch/);
  assert.match(files["plan.yml"],/name: Rulesets/);
  assert.match(files["plan.yml"],/name: Milestones/);
  assert.match(files["plan.yml"],/name: Projects/);
  assert.match(files["distribution.yml"],/name: Packages/);
  assert.match(files["distribution.yml"],/name: Releases/);
  assert.match(files["pipeline.yml"],/needs: \[quality, build, tests, plan, distribution\]/);
  assert.match(files["pipeline.yml"],/needs: build/);
  const push=render("ci/run-push-1122-1-abcdef0123",SHA,undefined,"push");
  assert.match(push["pipeline.yml"],/Native push build/);
  assert.match(push["build.yml"],/CI_EVENT: push/);
  assert.doesNotMatch(push["pipeline.yml"],/publish/);
  for(const source of Object.values(files)){
    assert.doesNotMatch(source,/publish:|id-token: write|secrets: inherit|pages: write/);
    assert.doesNotMatch(source,/actions\/checkout@v4/);
  }
});
test("preview refuses unexpected branches and SHA",()=>{
  assert.throws(()=>validate("main",SHA));
  assert.throws(()=>validate("../evil",SHA));
  assert.throws(()=>validate(BRANCH,"xyz"));
});
