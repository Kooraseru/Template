import fs from 'node:fs';
import path from 'node:path';
import { command, git, write, verifyDistribution, policy } from './core.mjs';
import { restore } from '../../security/receipts/github.mjs';

const read = file => JSON.parse(fs.readFileSync(file));
const directory = 'build/tmp/releases';
const operation = process.argv[2];
if (operation === 'prepare') {
  const entry = JSON.parse(process.env.CI_BUILD_SPEC);
  if (!new RegExp(policy.sha_pattern).test(entry.source_sha)) throw Error('Build source must be a full SHA');
  let reused = false;
  if (entry.accepted) {
    const staged = path.join('build/accepted-distributions', entry.artifact);
    if (fs.existsSync(staged)) {
      fs.cpSync(staged, 'build/artifacts', {recursive:true});
      const logs = path.join('build/accepted-logs', `build-logs-${entry.source_sha}-${entry.name}`);
      if (fs.existsSync(logs)) fs.cpSync(logs,'build/logs',{recursive:true});
    } else await restore(entry,'build/artifacts');
    verifyDistribution('build/artifacts',{...entry, accepted_source_sha:entry.accepted.source_sha});
    reused = true;
  }
  if (entry.cache_run && fs.existsSync('build/artifacts/provenance.json')) {
    try { verifyDistribution('build/artifacts', entry); reused = true; }
    catch (error) { console.warn(`Cached artifact rejected; rebuilding: ${error.message}`); fs.rmSync('build/artifacts', { recursive: true, force: true }); }
  }
  fs.mkdirSync(directory, { recursive: true });
  write(`${directory}/build-spec.json`, entry);
  const source = path.resolve('build/tmp/source', entry.source_sha);
  if (!reused) {
    // A standalone Git checkout preserves the selected HEAD for build commands
    // such as git describe. No worktree links, alternates, or ignored inputs.
    fs.rmSync(source, { recursive: true, force: true });
    fs.mkdirSync(source, { recursive: true });
    git(['clone', '--no-hardlinks', '--no-checkout', process.cwd(), source]);
    git(['-C', source, 'checkout', '--detach', entry.source_sha]);
    let origin = '';
    try { origin = git(['remote', 'get-url', 'origin']); } catch { /* a fixture may have no remote */ }
    if (origin) git(['-C', source, 'remote', 'set-url', 'origin', origin]);
    fs.mkdirSync(path.join(source, 'build'), { recursive: true });
  }
  if (process.env.GITHUB_OUTPUT) fs.appendFileSync(process.env.GITHUB_OUTPUT, `reused=${reused}\nsource_dir=${source}\n`);
  console.log(reused ? 'Verified cached distribution' : `Prepared source ${entry.source_sha}`);
} else if (operation === 'verify') {
  verifyDistribution(process.argv[3], JSON.parse(process.env.CI_BUILD_SPEC));
} else if (operation === 'assemble') {
  const { assemble } = await import('./render.mjs');
  await assemble(read(`${directory}/plan.json`));
} else if (operation === 'publish') {
  const { publish } = await import('./publish.mjs');
  await publish(process.env.RELEASE_VERSION);
} else if (operation === 'attest-protection') {
  const {api,repository,actor,isAdmin} = await import('../../security/receipts/github.mjs');
  const {protectionsValid} = await import('./core.mjs');
  if (process.env.ACT === 'true' || process.env.GITHUB_ACTIONS === 'true' || !isAdmin(actor())) throw Error('Enroll protection outside CI using an administrator login');
  const summaries = api(`repos/${repository()}/rulesets`);
  const rulesets = summaries.map(set => api(`repos/${repository()}/rulesets/${set.id}`));
  if (!protectionsValid(rulesets)) throw Error('Required source protections are absent');
  const file = 'build/reports/source-protection-attestation.json';
  write(file,{schema:1,repository:repository(),rulesets});
  command('gh',['variable','set','CI_SOURCE_PROTECTION','--repo',repository()],{input:fs.readFileSync(file)});
  console.log('Enrolled non-secret source protection snapshot; refresh after ruleset changes');
} else if (operation === 'protect') {
  const { protect } = await import('./publish.mjs');
  await protect(process.argv[3]);
} else throw Error(`Unknown operation: ${operation}`);
