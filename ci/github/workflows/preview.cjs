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

function validate(branch, sha) {
  if (!/^ci\/run-pr-[1-9]\d*-[a-f0-9]{7,12}$/.test(branch))
    throw new Error("Unsafe execution branch name");
  if (!/^[0-9a-f]{40}$/.test(sha)) throw new Error("Expected a complete source SHA");
}

function render(branch, sha, root=ROOT) {
  validate(branch,sha);
  const targets = hosts(root);
  const expr = name => "$" + "{{ " + name + " }}";
  const e = expr;
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
    "run-name: 'PR validation " + sha.slice(0,12) + "'",
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
    "    needs: start",
    "    permissions:",
    "      contents: read",
    "    uses: ./.github/workflows/tests.yml",
    "  build:",
    "    name: Build",
    "    needs: [quality, tests]",
    "    permissions:",
    "      contents: read",
    "    uses: ./.github/workflows/build.yml",
    "  collect:",
    "    name: Collect",
    "    needs: [quality, tests, build]",
    "    if: " + e("always()"),
    "    runs-on: ubuntu-latest",
    "    permissions: {}",
    "    steps:",
    "      - name: Verify all validation branches",
    "        env:",
    "          QUALITY: " + e("needs.quality.result"),
    "          TESTS: " + e("needs.tests.result"),
    "          BUILD: " + e("needs.build.result"),
    "        run: |",
    "          set -euo pipefail",
    '          test "$QUALITY" = success',
    '          test "$TESTS" = success',
    '          test "$BUILD" = success',
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
  ].join("\n") + "\n";
  const tests = [
    "name: Tests",
    "on:",
    "  workflow_call:",
    "permissions:",
    "  contents: read",
    "jobs:",
    "  universal:",
    "    name: Universal",
    "    runs-on: ubuntu-latest",
    "    timeout-minutes: 35",
    "    steps:",
    ...common,
    "      - run: bash ci/test.sh",
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
    "          CI_EVENT: pull_request",
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
    "          CI_EVENT: pull_request",
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
  const files={
    "pipeline.yml": pipeline,
    "quality.yml": quality,
    "tests.yml": tests,
    "build.yml": build,
  };
  for(const content of Object.values(files)){
    if (/publish:|pages: write|id-token: write|secrets: inherit|pull_request_target:/.test(content))
      throw new Error("Unsafe privileged instruction in preview workflow");
  }
  return files;
}

function main() {
  const branch=process.argv[2],sha=process.argv[3],output=process.argv[4]||"build/run/workflows";
  const files=render(branch,sha);
  fs.mkdirSync(output,{recursive:true});
  for(const [file,content] of Object.entries(files))fs.writeFileSync(path.join(output,file),content);
  process.stdout.write(JSON.stringify({branch,source:sha,files:Object.keys(files),hosts:hosts()})+"\n");
}
module.exports={hosts,render,validate};
if(require.main===module)main();
