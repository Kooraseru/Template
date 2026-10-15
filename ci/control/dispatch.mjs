import fs from 'node:fs';
import { actor, isAdmin } from '../receipts/github.mjs';
import { readRequest, parsePR, ignoresValidation, ignoresCoverage, diagnostic } from './request.mjs';

const controls = readRequest();
const manual = process.env.GITHUB_EVENT_NAME === 'workflow_dispatch';
if (manual && process.env.ACT !== 'true' && process.env.GITHUB_ACTIONS === 'true' && !isAdmin(actor())) {
  throw Error('The manual CI control panel requires repository administrator permission');
}
if (process.env.ACT === 'true' && controls.gate_policy !== 'Enforce all') throw Error('Gate overrides require hosted administrator execution');
const values = {
  operation: controls.operation, pr: parsePR(controls.pull_request),
  ignore_validation: manual && ignoresValidation(controls), ignore_coverage: manual && ignoresCoverage(controls),
  diagnostic: manual && diagnostic(controls),
};
if (process.env.GITHUB_OUTPUT) fs.appendFileSync(process.env.GITHUB_OUTPUT,
  Object.entries(values).map(([key, value]) => `${key}=${value}\n`).join(''));
if (process.env.GITHUB_STEP_SUMMARY) fs.appendFileSync(process.env.GITHUB_STEP_SUMMARY,
  '## CI control panel\n\n| Setting | Selection |\n| --- | --- |\n'
  + Object.entries(controls).map(([key, value]) => `| ${key} | ${value.replaceAll('|', '\\|').replaceAll('<', '&lt;')} |`).join('\n') + '\n');
