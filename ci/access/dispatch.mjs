import fs from 'node:fs';
import { actor, isAdmin } from '../receipts/github.mjs';

// Normalize the manual form once; automatic events retain the existing pipeline.
const event = process.env.GITHUB_EVENT_PATH
  ? JSON.parse(fs.readFileSync(process.env.GITHUB_EVENT_PATH, 'utf8')) : {};
const manual = process.env.GITHUB_EVENT_NAME === 'workflow_dispatch';
const inputs = event.inputs || {};
const operation = manual ? inputs.operation || 'Build' : 'Full Run';
const admin = inputs.admin || (inputs.bootstrap === 'true' ? 'First-time activation' : 'None');
if (!['Validate', 'Build', 'Publish', 'Full Run'].includes(operation)) throw Error('Unknown operation');
if (!['None', 'Ignore gates', 'First-time activation'].includes(admin)) throw Error('Unknown administrator control');
if (manual) {
  const target = inputs.target || (Number(inputs.pr) ? 'Pull request' : 'Source');
  if (!['Source', 'Pull request'].includes(target)) throw Error('Unknown target');
  if (target === 'Pull request' && !/^[1-9][0-9]*$/.test(inputs.pr || '')) throw Error('Enter a positive pull request number');
  if (target === 'Source' && inputs.pr && inputs.pr !== '0') throw Error('Source target requires an empty PR number');
  if (admin === 'First-time activation' && (target !== 'Pull request' || !['Build', 'Full Run'].includes(operation))) {
    throw Error('First-time activation requires a PR and Build or Full Run');
  }
  if (['Publish', 'Full Run'].includes(operation) && target === 'Pull request') throw Error('Publication requires Source; use Build for a PR');
  if (inputs.claim) JSON.parse(inputs.claim);
  if (admin !== 'None' && (process.env.ACT === 'true' || process.env.GITHUB_ACTIONS !== 'true' || !isAdmin(actor()))) {
    throw Error('Administrator controls require a hosted run requested by a repository administrator');
  }
}
const ignoreGates = manual && admin === 'Ignore gates';
if (process.env.GITHUB_OUTPUT) fs.appendFileSync(process.env.GITHUB_OUTPUT,
  `operation=${operation}\nignore_gates=${ignoreGates}\n`);
if (process.env.GITHUB_STEP_SUMMARY) fs.appendFileSync(process.env.GITHUB_STEP_SUMMARY,
  `## CI request\n\nOperation: ${operation}\n\nAdministrator control: ${manual ? admin : 'None'}\n`);
