import fs from 'node:fs';
import { spawnSync } from 'node:child_process';
import { readRequest } from './request.mjs';
import { git, write } from '../releases/core.mjs';

const groups = {
  Configuration: ['ci/validation/repository.luau', 'ci/validation/tests/config.luau', 'ci/validation/tests/catalogue.luau',
    'ci/validation/tests/artifacts.luau', 'ci/validation/tests/rules.luau', 'ci/validation/tests/gate.luau'],
  'Workflow rules': ['ci/validation/workflows.luau'],
  'Access policy': ['ci/access/tests/policy.luau', 'ci/access/tests/publication.luau', 'ci/control/tests/config.luau'],
  Receipts: ['ci/receipts/tests', 'ci/control/tests'],
  'Release tooling': ['ci/releases/tests'],
};
const controls = readRequest();
const evidence = { schema: 1, controller_sha: git(['rev-parse', 'HEAD']), tested_sha: process.env.CI_TESTED_SHA,
  controls, groups: [], created_at: new Date().toISOString() };
let failed = false;
for (const [name, paths] of Object.entries(groups)) {
  if (controls.validation_scope !== 'All' && controls.validation_scope !== name) continue;
  console.log(`::group::Validate / ${name}`);
  const checks = [];
  for (const file of paths) {
    const args = file.endsWith('.luau') ? ['run', file] : ['--test', ...fs.readdirSync(file)
      .filter(name => name.endsWith('.test.mjs')).map(name => `${file}/${name}`)];
    const result = spawnSync(file.endsWith('.luau') ? 'lune' : process.execPath, args, { stdio: 'inherit' });
    const success = result.status === 0 && !result.error;
    failed ||= !success;
    checks.push({ path: file, success, error: result.error?.message });
  }
  evidence.groups.push({ name, checks });
  console.log('::endgroup::');
}
evidence.success = !failed;
write('build/validation/evidence.json', evidence);
const planFile = 'build/tmp/releases/plan.json';
if (fs.existsSync(planFile)) {
  const plan = JSON.parse(fs.readFileSync(planFile));
  plan.validation = evidence;
  write(planFile, plan);
}
process.exitCode = failed ? 1 : 0;
