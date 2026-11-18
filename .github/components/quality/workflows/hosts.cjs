"use strict";
// Discover native host tests from tracked host contracts.
const fs = require("node:fs");
const path = require("node:path");
const ROOT = path.resolve(__dirname, "../../../..");
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

function matrix(root=ROOT) {
  return hosts(root).map(id=>{
    const {runner,expected}=nativeTest(root,id);
    return {id,runner,file:id+".exe",expected:["Hello from the shared C application!",expected]};
  });
}
module.exports={hosts,nativeTest,matrix};
if(require.main===module)process.stdout.write(JSON.stringify(matrix())+"\n");
