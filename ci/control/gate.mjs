import fs from 'node:fs';
import { readRequest, ignoresValidation, ignoresCoverage } from './request.mjs';

const controls = readRequest();
const results = JSON.parse(process.env.RESULTS);
const enabled = JSON.parse(process.env.ENABLED);
const errors = [];
if (results.validate.result !== 'success') errors.push('Input authorization or planning failed');
const plan = fs.existsSync('build/tmp/releases/plan.json') ? JSON.parse(fs.readFileSync('build/tmp/releases/plan.json')) : {};
if (plan.validation?.success === false && !ignoresValidation(controls)) errors.push('Selected validation checks failed');
if (controls.operation !== 'Validate') {
  if (results.build.result !== 'success') errors.push('Build or verified output restoration failed');
  for (const name of ['repository', 'pages', 'release', 'images']) {
    if (enabled[name] === 'true' && results[name].result !== 'success') errors.push(`${name} did not succeed`);
  }
  if (process.env.GITHUB_EVENT_NAME === 'workflow_dispatch' && !ignoresCoverage(controls)
      && results['validation-receipt'].result !== 'success') errors.push('Required receipt coverage is missing');
}
if (process.env.GITHUB_STEP_SUMMARY) fs.appendFileSync(process.env.GITHUB_STEP_SUMMARY,
  `## Gate\n\nPolicy: ${controls.gate_policy}\n\n${errors.length ? errors.join('\n\n') : 'Selected stages passed.'}\n`);
if (errors.length) throw Error(errors.join('; '));
console.log('CI gate passed');
