import fs from 'node:fs';
import path from 'node:path';
import test from 'node:test';
import assert from 'node:assert/strict';
import { spawnSync } from 'node:child_process';
import { runLuauCheck } from '../run-check.mjs';

const modules = ['repository', 'workflows', 'gate', 'tests/artifacts', 'tests/catalogue',
  'tests/config', 'tests/gate', 'tests/rules'].map(name => `ci/validation/${name}.luau`);
const ruleset = JSON.parse(fs.readFileSync('ci/validation/ruleset.json'));
const baseline = ruleset.gate.cases.baseline;
const env = { ...process.env, RESULTS: JSON.stringify(baseline.results), ENABLED: JSON.stringify(baseline.enabled) };

test('validation imports return modules without running checks, logging, or resetting fixtures', t => {
  const probe = `build/validation/import-probe-${process.pid}.luau`;
  const sentinels = [ruleset.artifacts.cases.root, ruleset.rules.cases.root].map(root => `${root}/import-preserved-${process.pid}`);
  fs.mkdirSync(path.dirname(probe), { recursive: true });
  for (const file of sentinels) {
    fs.mkdirSync(path.dirname(file), { recursive: true });
    fs.writeFileSync(file, 'preserved');
  }
  t.after(() => {
    for (const file of [probe, ...sentinels]) fs.rmSync(file, { force: true });
  });
  fs.writeFileSync(probe, modules.map(file => {
    const modulePath = '../../' + file.slice(0, -5);
    return `do\n local subject = require(${JSON.stringify(modulePath)})\n assert(type(subject) == "table" and type(subject.Run) == "function")\nend`;
  }).join('\n'));
  const result = spawnSync('lune', ['run', probe], { encoding: 'utf8', env: { ...env, RESULTS: '', ENABLED: '' } });
  assert.equal(result.status, 0, result.stderr);
  assert.equal(result.stdout, '');
  for (const file of sentinels) assert.equal(fs.readFileSync(file, 'utf8'), 'preserved');
});

test('CI adapter calls Run on every validation module and preserves rejection failures', () => {
  for (const file of modules) {
    const result = runLuauCheck(file, { encoding: 'utf8', env });
    assert.equal(result.status, 0, `${file}: ${result.stderr}`);
    assert.equal(result.stdout, '', `${file} logged instead of returning to its caller`);
  }
  const failed = structuredClone(baseline.results);
  failed.validate.result = 'failure';
  const result = runLuauCheck('ci/validation/gate.luau', {
    encoding: 'utf8', env: { ...env, RESULTS: JSON.stringify(failed) },
  });
  assert.notEqual(result.status, 0, 'Run must propagate validation failures to CI');
});
