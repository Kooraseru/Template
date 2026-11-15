"use strict";
// Generate a build-only, read-only native GitHub workflow from tracked host
// contracts. No publishing jobs, protected environments or credentials.
const fs = require("node:fs");
const path = require("node:path");
const ROOT = path.resolve(__dirname, "../../..");
const VALID = /^[a-z][a-z0-9-]*$/;

function hosts(root = ROOT) {
  const directory = path.join(root, "source/hosts");
  const found = [];
  for (const entry of fs.readdirSync(directory, { withFileTypes: true })) {
    if (!entry.isDirectory() || !VALID.test(entry.name)) continue;
    const base = path.join(directory, entry.name);
    const contract = path.join(base, "host.toml");
    if (!fs.existsSync(contract)) continue;
    if (!fs.statSync(contract).isFile() || !fs.statSync(path.join(base,"init.luau")).isFile())
      throw new Error("Incomplete host contract: " + entry.name);
    const source = fs.readFileSync(contract, "utf8");
    if (!source.includes('build/artifacts/application/' + entry.name + '.exe'))
      throw new Error("Unexpected host artifact: " + entry.name);
    found.push(entry.name);
  }
  if (!found.length) throw new Error("No host contracts were discovered");
  return found.sort();
}

function nativeTest(root, target) {
  const source = fs.readFileSync(path.join(root, "source/hosts", target, "host.toml"), "utf8");
  const fields = Object.fromEntries(
    [...source.matchAll(/^([a-z_]+)\s*=\s*"([^"\r\n]+)"\s*$/gm)].map(match => [match[1], match[2]])
  );
  const runner = fields.test_runner, expected = fields.test_expected;
  if (!runner || !/^(?:windows-latest|windows-11-arm|windows-2025|windows-11-vs2026-arm)$/.test(runner) ||
      !expected || /[\r\n]/.test(expected)) {
    throw new Error("Invalid native test runner/expectation for " + target);
  }
  return { runner, expected };
}

function validate(branch, sha) {
  if (!/^ci\/run-(?:pr-[1-9]\d*|push-[1-9]\d*-[1-9]\d*)-[a-f0-9]{7,12}$/.test(branch))
    throw new Error("Unsafe execution branch name");
  if (!/^[0-9a-f]{40}$/.test(sha)) throw new Error("Expected a complete source SHA");
}

function render(branch, sha, root=ROOT, event='pull_request') {
  validate(branch,sha);
  if (!['pull_request','push'].includes(event)) throw new Error('Only build-only push and PR graphs are supported');
  const targets = hosts(root);
  const expr = name => "$" + "{{ " + name + " }}";
  const e = expr;
  const componentEvent = event;
  const common = [
    "      - uses: actions/checkout@v7",
    "        with:",
    "          persist-credentials: false",
    "          ref: " + sha,
    "      - uses: actions/setup-node@v7.1.0",
    "        with:",
    "          node-version: '24'",
  ];
  const pipeline = [
    "name: Generated CI",
    "run-name: 'Native " + (event === "push" ? "push" : "PR") + " build " + sha.slice(0,12) + "'",
    "on:",
    "  push:",
    "    branches: ['" + branch + "']",
    "permissions: {}",
    "jobs:",
    "  start:",
    "    name: Start",
    "    runs-on: ubuntu-latest",
    "    permissions: {}",
    "    steps:",
    "      - name: Identify immutable PR revision",
    "        run: echo 'Validating PR SHA " + sha + "'",
    "  quality:",
    "    name: Quality",
    "    needs: start",
    "    permissions:",
    "      contents: read",
    "    uses: ./.github/workflows/quality.yml",
    "  tests:",
    "    name: Tests",
    "    needs: build",
    "    permissions:",
    "      contents: read",
    "      actions: read",
    "    uses: ./.github/workflows/tests.yml",
    "  build:",
    "    name: Build",
    "    needs: start",
    "    permissions:",
    "      contents: read",
    "    uses: ./.github/workflows/build.yml",
    "  plan:",
    "    name: Plan",
    "    needs: start",
    "    permissions:",
    "      contents: read",
    "    uses: ./.github/workflows/plan.yml",
    "  distribution:",
    "    name: Distribution",
    "    needs: build",
    "    permissions:",
    "      contents: read",
    "      actions: read",
    "    uses: ./.github/workflows/distribution.yml",
    "  collect:",
    "    name: Collect",
    "    needs: [quality, build, tests, plan, distribution]",
    "    if: " + e("always()"),
    "    runs-on: ubuntu-latest",
    "    permissions: {}",
    "    steps:",
    "      - name: Verify all validation branches",
    "        env:",
    "          QUALITY: " + e("needs.quality.result"),
    "          TESTS: " + e("needs.tests.result"),
    "          BUILD: " + e("needs.build.result"),
    "          PLAN: " + e("needs.plan.result"),
    "          DISTRIBUTION: " + e("needs.distribution.result"),
    "        run: |",
    "          set -euo pipefail",
    '          test "$QUALITY" = success',
    '          test "$TESTS" = success',
    '          test "$BUILD" = success',
    '          test "$PLAN" = success',
    '          test "$DISTRIBUTION" = success',
  ].join("\n") + "\n";
  const quality = [
    "name: Quality",
    "on:",
    "  workflow_call:",
    "permissions:",
    "  contents: read",
    "jobs:",
    "  review:",
    "    name: Review",
    "    runs-on: ubuntu-latest",
    "    steps:",
    ...common,
    "      - run: node dependencies/packages/core/dependencyLoader/index.ts",
    "      - run: node ci/code-review.cjs",
    "  rules:",
    "    name: Rules",
    "    runs-on: ubuntu-latest",
    "    steps:",
    ...common,
    "      - run: node dependencies/packages/core/dependencyLoader/index.ts",
    "      - run: node ci/rules-audit.cjs",
    "  workflows:",
    "    name: Workflows",
    "    runs-on: ubuntu-latest",
    "    steps:",
    ...common,
    "      - run: bash ci/bootstrap/check-workflows.sh",
    "  updates:",
    "    name: Updates",
    "    runs-on: ubuntu-latest",
    "    steps:",
    ...common,
    "      - run: node ci/template/version.cjs",
  ].join("\n") + "\n";
  const nativeTests = targets.flatMap(target => [
    "          - target: " + target,
    "            label: " + target.replace(/(^|-)([a-z])/g, (_,p,c)=>(p?" ":"")+c.toUpperCase()),
    "            runner: " + nativeTest(root,target).runner,
    "            expected: " + JSON.stringify(nativeTest(root,target).expected),
  ]);
  const tests = [
    "name: Tests",
    "on:",
    "  workflow_call:",
    "permissions:",
    "  contents: read",
    "  actions: read",
    "jobs:",
    "  universal:",
    "    name: Universal",
    "    runs-on: ubuntu-latest",
    "    timeout-minutes: 35",
    "    steps:",
    ...common,
    "      - run: bash ci/test.sh",
    "  native:",
    "    name: " + e("matrix.label"),
    "    strategy:",
    "      fail-fast: false",
    "      matrix:",
    "        include:",
    ...nativeTests,
    "    runs-on: " + e("matrix.runner"),
    "    timeout-minutes: 20",
    "    steps:",
    "      - uses: actions/download-artifact@v8",
    "        with:",
    "          name: " + e("matrix.target"),
    "          path: verified",
    "      - name: Run and verify " + e("matrix.target"),
    "        shell: pwsh",
    "        env:",
    "          TARGET: " + e("matrix.target"),
    "          EXPECTED: " + e("matrix.expected"),
    "        run: |",
    '          $ErrorActionPreference = "Stop"',
    '          $binary = Join-Path $PWD ("verified/" + $env:TARGET + ".exe")',
    '          if (!(Test-Path $binary)) { throw "Missing built executable: $binary" }',
    '          $lines = @(& $binary)',
    '          if ($LASTEXITCODE -ne 0) { throw "Executable exited with $LASTEXITCODE" }',
    '          if ($lines -notcontains "Hello from the shared C application!") { throw "Shared application smoke test failed" }',
    '          if ($lines -notcontains $env:EXPECTED) { throw "Host-specific output mismatch: $env:EXPECTED" }',
  ].join("\n") + "\n";
  const matrix=targets.flatMap(target=>[
    "          - target: " + target,
    "            label: " + target.replace(/(^|-)([a-z])/g, (_,p,c)=>(p?" ":"")+c.toUpperCase()),
    "            runner: ubuntu-latest",
  ]);
  const auxiliary = [
    ["pages", "Pages", "documentation/pages/build", "build/github/pages/"],
    ["branches", "Branches", "governance/branches/build", "build/github/branches/"],
  ].flatMap(([id, label, component, artifact]) => [
    "  " + id + ":",
    "    name: " + label,
    "    runs-on: ubuntu-latest",
    "    timeout-minutes: 25",
    "    steps:",
    ...common,
    "      - name: Build " + label,
    "        env:",
    "          CI_EVENT: " + componentEvent,
    "          CI_GRAPH_RUN: 'true'",
    "          CI_OPERATION: validation",
    "        run: node dependencies/packages/core/dependencyLoader/index.ts --exec luau.lute run ci/entry.luau --component " + component,
    "      - uses: actions/upload-artifact@v7",
    "        with:",
    "          name: " + id,
    "          path: " + artifact,
    "          if-no-files-found: error",
  ]);
  const build = [
    "name: Build",
    "on:",
    "  workflow_call:",
    "permissions:",
    "  contents: read",
    "jobs:",
    "  host:",
    "    name: " + e("matrix.label"),
    "    strategy:",
    "      fail-fast: false",
    "      matrix:",
    "        include:",
    ...matrix,
    "    runs-on: " + e("matrix.runner"),
    "    timeout-minutes: 45",
    "    steps:",
    ...common,
    "      - name: Compile " + e("matrix.target"),
    "        env:",
    "          CI_EVENT: " + componentEvent,
    "          CI_GRAPH_RUN: 'true'",
    "          CI_OPERATION: validation",
    "          CI_HOST_TARGET: " + e("matrix.target"),
    "        run: node dependencies/packages/core/dependencyLoader/index.ts --exec luau.lute run ci/entry.luau --component source/build",
    "      - name: Upload executable",
    "        uses: actions/upload-artifact@v7",
    "        with:",
    "          name: " + e("matrix.target"),
    "          path: build/artifacts/application/" + e("matrix.target") + ".exe",
    "          if-no-files-found: error",
    ...auxiliary,
  ].join("\n") + "\n";
  const planComponents = [
    ["rulesets", "Rulesets", "governance/rulesets/plan", "build/github/ruleset-plans/"],
    ["milestones", "Milestones", "work/milestones/plan", "build/github/milestones/"],
    ["projects", "Projects", "work/projects/plan", "build/github/project-plans/"],
  ];
  const plan = [
    "name: Plan", "on:", "  workflow_call:", "permissions:", "  contents: read", "jobs:",
    ...planComponents.flatMap(([id, label, component, artifact]) => [
      "  " + id + ":", "    name: " + label, "    runs-on: ubuntu-latest",
      "    timeout-minutes: 25", "    steps:", ...common,
      "      - name: Plan " + label,
      "        env:", "          CI_EVENT: " + componentEvent,
      "          CI_GRAPH_RUN: 'true'", "          CI_OPERATION: validation",
      "        run: node dependencies/packages/core/dependencyLoader/index.ts --exec luau.lute run ci/entry.luau --component " + component,
      "      - uses: actions/upload-artifact@v7",
      "        with:", "          name: plan-" + id,
      "          path: " + artifact, "          if-no-files-found: error",
    ]),
  ].join("\n") + "\n";
  const distributionComponents = [
    ["packages", "Packages", "distribution/packages/build", "build/github/packages/"],
    ["releases", "Releases", "distribution/releases/build", "build/github/releases/"],
  ];
  const distribution = [
    "name: Distribution", "on:", "  workflow_call:",
    "permissions:", "  contents: read", "  actions: read", "jobs:",
    ...distributionComponents.flatMap(([id,label,component,artifact])=>[
      "  " + id + ":", "    name: " + label, "    runs-on: ubuntu-latest",
      "    timeout-minutes: 30", "    steps:", ...common,
      "      - uses: actions/download-artifact@v8",
      "        with:", "          pattern: windows-*",
      "          merge-multiple: true",
      "          path: build/artifacts/application",
      "      - name: Build " + label,
      "        env:", "          CI_EVENT: " + componentEvent,
      "          CI_OPERATION: validation", "          CI_GRAPH_RUN: 'true'",
      "          CI_NATIVE_PREVIEW: 'true'",
      "        run: node dependencies/packages/core/dependencyLoader/index.ts --exec luau.lute run ci/entry.luau --component " + component,
      "      - uses: actions/upload-artifact@v7",
      "        with:", "          name: distribution-" + id,
      "          path: " + artifact,
      "          if-no-files-found: error",
    ]),
  ].join("\n") + "\n";
  const files={
    "pipeline.yml": pipeline,
    "quality.yml": quality,
    "tests.yml": tests,
    "build.yml": build,
    "plan.yml": plan,
    "distribution.yml": distribution,
  };
  for(const content of Object.values(files)){
    if (/publish:|pages: write|id-token: write|secrets: inherit|pull_request_target:/.test(content))
      throw new Error("Unsafe privileged instruction in preview workflow");
  }
  return files;
}

function main() {
  const branch=process.argv[2],sha=process.argv[3],output=process.argv[4]||"build/run/workflows",event=process.argv[5]||"pull_request";
  const files=render(branch,sha,ROOT,event);
  fs.mkdirSync(output,{recursive:true});
  for(const [file,content] of Object.entries(files))fs.writeFileSync(path.join(output,file),content);
  process.stdout.write(JSON.stringify({branch,source:sha,files:Object.keys(files),hosts:hosts()})+"\n");
}
module.exports={hosts,nativeTest,render,validate};
if(require.main===module)main();
