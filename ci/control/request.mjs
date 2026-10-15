import fs from 'node:fs';
import { parseVersion } from '../releases/core.mjs';

export const definitions = JSON.parse(fs.readFileSync(new URL('./options.json', import.meta.url)));
export const catalogue = JSON.parse(fs.readFileSync(new URL('../build/targets.json', import.meta.url))).targets;

export function pullRequestLabel(pr) {
  if (!Number.isSafeInteger(pr.number) || pr.number <= 0) throw Error('Invalid PR identity');
  const title = String(pr.title).replace(/[\x00-\x1f\x7f]/g, ' ').replace(/\s+/g, ' ').trim()
    .replaceAll('${{', '$ { {').slice(0, 100);
  return `#${pr.number} ${title}`;
}

export function parsePR(value = 'Source') {
  if (value === 'Source') return 0;
  const match = /^#([1-9][0-9]*)(?: .*)?$/.exec(value);
  if (!match || !Number.isSafeInteger(Number(match[1]))) throw Error('Select Source or a pull request from the dropdown');
  return Number(match[1]);
}

export function normalize(inputs = {}, manual = true) {
  if (Object.keys(inputs).some(key => !(key in definitions))) throw Error('Unknown CI setting');
  const controls = {};
  for (const [key, definition] of Object.entries(definitions)) {
    const value = inputs[key] ?? definition.default;
    const choices = key === 'build_targets' ? [...definition.options, ...catalogue.map(target => target.name)] : definition.options;
    if (definition.type === 'string') {
      if (typeof value !== 'string') throw Error(`Invalid ${key}`);
    } else if (key === 'pull_request') parsePR(value);
    else if (!choices.includes(value)) throw Error(`Unknown ${key}: ${value}`);
    controls[key] = value;
  }
  if (!manual) controls.operation = 'Full Run';
  const pr = parsePR(controls.pull_request);
  if (pr && ['Publish', 'Full Run'].includes(controls.operation)) throw Error('Publication requires Source; select Validate or Build for a PR');
  if (controls.operation === 'Publish' && controls.cache_policy.startsWith('Rebuild')) throw Error('Publish cannot rebuild; select Full Run');
  if (Boolean(controls.release_version) !== Boolean(controls.release_commit)) throw Error('Release version and source commit must be supplied together');
  if (controls.release_version) {
    const version = parseVersion(controls.release_version);
    if (!/^[a-f0-9]{40}$/.test(controls.release_commit)) throw Error('Release source commit must be a full 40-character SHA');
    if (pr) throw Error('Explicit public version selection requires Source');
    if (controls.release_output.startsWith('Publish ') && controls.release_output !== `Publish ${version.type}`) {
      throw Error('Release output type does not match the selected SemVer version');
    }
  }
  return controls;
}

export function readRequest(env = process.env) {
  const event = env.GITHUB_EVENT_PATH ? JSON.parse(fs.readFileSync(env.GITHUB_EVENT_PATH, 'utf8')) : {};
  return normalize(env.GITHUB_EVENT_NAME === 'workflow_dispatch' ? event.inputs : {}, env.GITHUB_EVENT_NAME === 'workflow_dispatch');
}

export const ignoresValidation = controls => ['Ignore validation failures', 'Ignore both'].includes(controls.gate_policy);
export const ignoresCoverage = controls => ['Ignore incomplete coverage', 'Ignore both'].includes(controls.gate_policy);
export const diagnostic = controls => controls.validation_scope !== 'All' || controls.gate_policy !== 'Enforce all'
  || controls.build_targets !== 'Configured' || controls.compiler !== 'Any' || controls.architecture !== 'Any';

export function diagnosticReuseAllowed(receipt, env = process.env) {
  if (env.CI_PUBLICATION_JOB === 'true' || env.GITHUB_EVENT_NAME !== 'workflow_dispatch') return false;
  const controls = readRequest(env);
  return diagnostic(controls) && receipt.controls && ['validation_scope', 'build_targets', 'compiler', 'architecture', 'gate_policy']
    .every(key => receipt.controls[key] === controls[key]);
}
