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
  if (results.build.result !== 'success') errors.push(results.build.result === 'skipped'
    ? (plan.context?.source_authorization ? 'Administrator-approved source run skipped required builds; check job routing'
      : 'No administrator execution approval or matching stored builds were found')
    : 'Build or verified output restoration failed');
  for (const name of ['repository', 'pages', 'release', 'images']) {
    if (enabled[name] === 'true' && results[name].result !== 'success') errors.push(`${name} did not succeed`);
  }
  if ((process.env.GITHUB_EVENT_NAME === 'workflow_dispatch' || plan.context?.source_authorization) && !ignoresCoverage(controls)
      && results['validation-receipt'].result !== 'success') errors.push('Required receipt coverage is missing');
}
if (process.env.GITHUB_STEP_SUMMARY) fs.appendFileSync(process.env.GITHUB_STEP_SUMMARY,
  `## Gate\n\nPolicy: ${controls.gate_policy}\n\n`
  + (plan.context?.source_authorization ? `Source approval: ${plan.context.source_authorization.kind} by ${plan.context.source_authorization.actor}.\n\n` : '')
  + `${errors.length ? errors.join('\n\n') : 'Selected stages passed.'}\n`);
if (errors.length) throw Error(errors.join('; '));
console.log('CI gate passed');
