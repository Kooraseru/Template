// Temporary interoperability for the remaining Node release/receipt tooling and its tests.
// Behavior lives in Luau. Remove this boundary when those consumers are ported.
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { spawnSync } from 'node:child_process';

const root = fileURLToPath(new URL('../../', import.meta.url));
const generated = path.join(root, 'build/luau');

function invocation(source, options = {}, args = []) {
  fs.mkdirSync(generated, { recursive: true });
  const directory = fs.mkdtempSync(path.join(generated, 'node-'));
  const adapter = path.join(directory, 'invoke.luau');
  try {
    fs.writeFileSync(adapter, '-- Generated interoperability adapter.\n' + source);
    return spawnSync('lune', ['run', adapter, ...args], options);
  } finally {
    fs.rmSync(directory, { recursive: true, force: true });
  }
}

function evaluate(module, member, args) {
  const source = `local Serde = require("@lune/serde")
local Stdio = require("@lune/stdio")
local Subject = require("../../../${module.slice(0, -5)}")
local arguments = Serde.decode("json", ${JSON.stringify(JSON.stringify(args))})
local value = Subject.${member}(table.unpack(arguments, 1, ${args.length}))
Stdio.write(Serde.encode("json", {value = value}))
`;
  const result = invocation(source, { encoding: 'utf8', maxBuffer: 64 * 1024 * 1024 });
  if (result.error) throw result.error;
  if (result.status !== 0) throw Error(result.stderr);
  return JSON.parse(result.stdout).value ?? null;
}

function environment(env) {
  const keys = ['ACT', 'GITHUB_EVENT_PATH', 'GITHUB_EVENT_NAME', 'GITHUB_ACTIONS', 'GITHUB_SERVER_URL',
    'GITHUB_REF', 'GITHUB_ACTOR', 'GITHUB_REPOSITORY', 'GITHUB_SHA', 'GITHUB_RUN_ID', 'CI_PUBLICATION_JOB'];
  return Object.fromEntries(keys.filter(key => env[key] !== undefined).map(key => [key, env[key]]));
}

export const parseVersion = version => evaluate('publication/releases/versions.luau', 'Parse', [version]);
export const validateReleases = (document, tip, repository = '.') => {
  const selections = evaluate('publication/releases/versions.luau', 'Validate', [document, tip, repository]);
  return Array.isArray(selections) ? selections : [];
};
export const selectReleases = (document, controls, tip, repository = '.') => {
  const selections = evaluate('publication/releases/versions.luau', 'Select', [document, controls, tip, repository]);
  return Array.isArray(selections) ? selections : [];
};

export const parsePR = (value = 'Source') => evaluate('.github/integration/request.luau', 'ParsePR', [value]);
export const pullRequestLabel = pr => evaluate('.github/integration/request.luau', 'PullRequestLabel', [pr]);
export const readRequest = (env = process.env) => evaluate('.github/integration/request.luau', 'Read', [environment(env)]);
export const diagnostic = controls => evaluate('.github/integration/request.luau', 'Diagnostic', [controls]);
export const diagnosticReuseAllowed = (receipt, env = process.env) => evaluate('.github/integration/request.luau', 'DiagnosticReuseAllowed', [receipt, environment(env)]);
export const pendingReceiptAllowed = (run, env = process.env) => evaluate('.github/integration/pending-receipt.luau', 'Allowed', [run, environment(env)]);
export const sourceApproval = (env = process.env) => evaluate('.github/integration/source-approval.luau', 'Read', [environment(env)]);
export const authorizePublication = (env = process.env) => evaluate('.github/integration/publication.luau', 'Authorize', [environment(env)]);

// Keep receipt JSON intact until the Luau byte-preserving parser receives it.
// Keys/private material are never passed to this generated-source boundary.
function receiptCall(operation, values, now) {
  if (!['Validate', 'Applicable', 'ExecutionValid', 'Compare'].includes(operation)) throw Error('Invalid receipt operation');
  if (now !== undefined && (typeof now !== 'number' || !Number.isFinite(now))) throw TypeError('Invalid receipt validation time');
  const argumentsSource = values.map(value => `Canonical.Decode(${JSON.stringify(JSON.stringify(value))})`);
  if (now !== undefined) argumentsSource.push(String(now));
  const source = `local Canonical = require("../../../libraries/bootstrap/canonical")
local Subject = require("../../../security/receipts/verification")
local Stdio = require("@lune/stdio")
local value = Subject.${operation}(${argumentsSource.join(', ')})
${operation === 'Compare' ? 'value = Canonical.Array(value)' : ''}
Stdio.write(assert(Canonical.Encode(value)))
`;
  const result = invocation(source, { cwd: root, encoding: 'utf8', maxBuffer: 64 * 1024 * 1024 });
  if (result.error) throw result.error;
  if (result.status !== 0) throw Error(result.stderr);
  return JSON.parse(result.stdout);
}

export function validateReceipt(receipt, now = Date.now()) {
  receiptCall('Validate', [receipt], now);
  return receipt;
}
export const receiptApplicable = (target, entry) => receiptCall('Applicable', [target, entry]);
export const receiptExecutionValid = (target, entry) => receiptCall('ExecutionValid', [target, entry]);
export const compareReceipts = (claim, accepted) => receiptCall('Compare', [claim, accepted], Date.now());

export function runLuauCheck(file, options = {}, args = []) {
  if (!/^(?:\.github\/integration|config\/tools|libraries|validation|fabricator|security|publication)\/(?:[a-z-]+\/)*[a-z-]+\.luau$/.test(file)) throw Error('Invalid Luau module path');
  return invocation(`local subject = require("../../../${file.slice(0, -5)}")\nif subject.Cases then subject:Run() else subject.Run() end\n`, options, args);
}
