import fs from 'node:fs';
import path from 'node:path';
import crypto from 'node:crypto';
import { canonical, command, git, sha256, write } from '../releases/core.mjs';
import { bundle, clean, collect, compare, identity, manifest, policy, sign, validate, verifyBundle } from './core.mjs';
import { actor, api, assertAdminWriters, currentPR, discover, freshPR, isAdmin, merge, predatesContract, repository, setCheck, upload, verifyEnvelope } from './github.mjs';

const read = file => JSON.parse(fs.readFileSync(file));
const root = 'build/tmp/receipts';
const operation = process.argv[2];
function output(values) {
  if (process.env.GITHUB_OUTPUT) fs.appendFileSync(process.env.GITHUB_OUTPUT, Object.entries(values).map(([key,value]) => `${key}=${value}\n`).join(''));
}
function environment(values) {
  if (process.env.GITHUB_ENV) fs.appendFileSync(process.env.GITHUB_ENV, Object.entries(values).map(([key,value]) => `${key}=${value}\n`).join(''));
}
if (operation === 'authorize') {
  const event = process.env.GITHUB_EVENT_PATH ? read(process.env.GITHUB_EVENT_PATH) : {};
  const local = process.env.ACT === 'true' || process.env.GITHUB_ACTIONS !== 'true';
  if (!local) assertAdminWriters();
  const dispatch = process.env.GITHUB_EVENT_NAME === 'workflow_dispatch';
  const number = Number(event.inputs?.pr || event.pull_request?.number || process.env.CI_RECEIPT_PR || 0);
  let pr, testedSHA = process.env.CI_TESTED_SHA || git(['rev-parse','HEAD']);
  if (local) {
    clean();
    pr = event.receipt_context || { number, head_sha: testedSHA, base_sha: git(['rev-parse','HEAD']) };
    testedSHA = pr.head_sha;
  } else if (number) {
    pr = currentPR(number); testedSHA = pr.head_sha;
  } else pr = { number: 0, head_sha: testedSHA, base_sha: testedSHA };
  const requested = local || dispatch;
  const bootstrap = !local && dispatch && (event.inputs?.admin === 'First-time activation' || event.inputs?.bootstrap === 'true');
  if (!local && dispatch && (!isAdmin(actor()) || (process.env.GITHUB_REF !== 'refs/heads/source'
    && !(bootstrap && number && pr.head_sha === process.env.GITHUB_SHA && predatesContract(pr.base_sha))))) throw Error('Hosted validation requires an administrator and the source controller');
  if (bootstrap && (pr.head_sha !== process.env.GITHUB_SHA || !predatesContract(pr.base_sha))) throw Error('Bootstrap is restricted to the first activation PR');
  if (!local && testedSHA !== git(['rev-parse','HEAD'])) {
    const env = { ...process.env, GIT_CONFIG_COUNT: '1', GIT_CONFIG_KEY_0: 'http.https://github.com/.extraheader',
      GIT_CONFIG_VALUE_0: 'AUTHORIZATION: basic ' + Buffer.from(`x-access-token:${process.env.GH_TOKEN}`).toString('base64') };
    git(['fetch','--no-tags','origin',testedSHA], { env });
  }
  const context = { repository: process.env.GITHUB_REPOSITORY || repository(), tested_sha: testedSHA, pr, requested,
    local, bootstrap, event: process.env.GITHUB_EVENT_NAME || 'local', claim: event.inputs?.claim || '' };
  write(`${root}/context.json`, context);
  environment({ CI_TESTED_SHA: testedSHA, CI_VALIDATION_REQUESTED: String(requested), CI_RECEIPT_PR: String(number) });
  output({ requested: String(requested), tested_sha: testedSHA });
} else if (operation === 'plan') {
  const plan = read('build/tmp/releases/plan.json');
  const context = read(`${root}/context.json`);
  plan.context = context; plan.tested_sha = context.tested_sha;
  if (!context.local) await discover(plan, context.pr.number ? context.pr : null, true);
  const complete = plan.builds.every(entry => entry.accepted);
  const run = context.requested || complete;
  const names = process.env.CI_LOCAL_TARGETS ? JSON.parse(process.env.CI_LOCAL_TARGETS) : null;
  if (names && (!context.local || !Array.isArray(names) || !names.length
    || names.some(name => !plan.builds.some(entry => entry.name === name)))) throw Error('Local target selection is invalid');
  const executing = context.local ? plan.builds.filter(entry => entry.runner.startsWith('ubuntu')
    && (!names || names.includes(entry.name))) : plan.builds;
  const event = process.env.GITHUB_EVENT_PATH ? read(process.env.GITHUB_EVENT_PATH) : {};
  if (event.inputs?.operation === 'Publish' && !complete) throw Error('Publish requires matching accepted cached outputs; run Build first');
  const requiredImages = new Set(executing.filter(entry => !entry.accepted).map(entry => entry.image_artifact));
  plan.images = run ? plan.images.filter(entry => requiredImages.has(entry.artifact)) : [];
  write('build/tmp/releases/plan.json', plan);
  const previous = read('build/tmp/releases/outputs.json');
  previous.images_enabled = String(plan.images.length > 0);
  previous.image_matrix = JSON.stringify({ include: plan.images.length ? plan.images : [{ name:'disabled', runner:'ubuntu-latest', artifact:'disabled', input_ref:'' }] });
  previous.build_matrix = JSON.stringify({ include: run ? executing : [{ name:'disabled', runner:'ubuntu-latest', input_ref:'' }] });
  previous.build_requested = String(run); previous.receipt_ready = String(complete);
  previous.release_enabled = String(run && plan.selections.length > 0 && executing.length === plan.builds.length);
  previous.local_execution = String(context.local);
  previous.accepted_available = String(plan.builds.some(entry => entry.accepted));
  write('build/tmp/releases/outputs.json', previous);
  console.log(complete ? 'Accepted validation covers all targets' : context.requested ? 'Admin/local execution requested' : 'Waiting for admin validation; expensive jobs remain disabled');
} else if (operation === 'execution') {
  const spec = JSON.parse(process.env.CI_BUILD_SPEC);
  const selected = identity(spec.source_sha);
  const imageRecord = spec.image ? read('build/selected-image/image.json') : null;
  if (imageRecord && (!/^sha256:[a-f0-9]{64}$/.test(imageRecord.id)
    || imageRecord.os + '/' + imageRecord.architecture !== spec.platform)) throw Error('Actual image identity or platform mismatch');
  const execution = spec.image ? { kind:'container', os:'linux', arch: spec.platform.endsWith('arm64') ? 'arm64' : 'x64',
    host_os:process.platform, host_arch:process.arch, image_archive_sha256:sha256(fs.readFileSync('build/selected-image/image.tar')),
    image_record:imageRecord } : { kind:'native', os:process.platform, arch:process.arch };
  execution.probe_logs = manifest('build/logs').filter(file => /^probe-\d+\.log$/.test(file.path));
  execution.node_version = process.version;
  write('build/tmp/releases/execution.json', { schema:1, ...selected,
    fingerprint:spec.fingerprint, target:spec.name, controller_sha:process.env.GITHUB_SHA || 'local', execution,
    resolved_fingerprint:sha256(canonical({inputs:spec.fingerprint,execution})) });
} else if (operation === 'collect') {
  const plan = read(process.argv[3] || 'build/tmp/releases/plan.json');
  const context = plan.context || read(`${root}/context.json`);
  const receipt = collect(plan, process.argv[4] || 'build/distributions', process.argv[5] || 'build/validation-logs', context);
  const destination = process.argv[6] || 'build/receipts';
  const bundleRoot = path.join(destination, 'bundle');
  if (fs.existsSync(bundleRoot)) throw Error('Receipt bundle destination must be fresh');
  bundle(bundleRoot, receipt, process.argv[4] || 'build/distributions', process.argv[5] || 'build/validation-logs');
  const archive = path.join(destination, policy.archive_asset);
  command('tar',['-czf',archive,'-C',bundleRoot,'.']);
  receipt.bundle_sha256 = sha256(fs.readFileSync(archive));
  verifyBundle(bundleRoot, receipt);
  write(path.join(destination,policy.receipt_asset), { receipt, authentication:{kind:'claim'} });
  console.log(`Collected ${receipt.targets.length} executed targets at ${destination}`);
} else if (operation === 'local-context') {
  clean();
  const pr = currentPR(Number(process.argv[3]));
  const controller = api(`repos/${repository()}/git/ref/heads/source`).object.sha;
  const head = git(['rev-parse','HEAD']);
  const bootstrap = process.argv.includes('--bootstrap') && head === pr.head_sha
    && isAdmin(actor()) && predatesContract(pr.base_sha);
  if (head !== controller && !bootstrap) throw Error('Admin local validation must use a clean source controller checkout');
  const token = command('gh',['auth','token']).trim();
  git(['fetch','--no-tags','origin',pr.head_sha],{env:{...process.env,GIT_CONFIG_COUNT:'1',
    GIT_CONFIG_KEY_0:'http.https://github.com/.extraheader',GIT_CONFIG_VALUE_0:'AUTHORIZATION: basic ' + Buffer.from(`x-access-token:${token}`).toString('base64')}});
  write(process.argv[4] || 'build/tmp/receipts/event.json',{inputs:{pr:String(pr.number)},receipt_context:pr});
} else if (operation === 'claim-context') {
  clean();
  const pr = currentPR(Number(process.argv[3]));
  if (git(['rev-parse','HEAD']) !== pr.head_sha) throw Error('Contributor checkout must match the current PR head');
  write(process.argv[4] || 'build/tmp/receipts/event.json',{inputs:{pr:String(pr.number)},receipt_context:pr});
} else if (operation === 'claim-submit') {
  if (process.env.ACT === 'true' || process.env.GITHUB_ACTIONS === 'true') throw Error('Submit claims outside execution environments');
  const envelope = read(process.argv[3]);validate(envelope.receipt);freshPR(envelope.receipt);
  if (!envelope.receipt.pr.number) throw Error('A contributor claim needs an open PR context');
  const body = 'Local CI claim; requires independent admin validation.\n\n```json\n'
    + JSON.stringify({receipt:envelope.receipt,authentication:{kind:'claim'}}) + '\n```';
  if (body.length > 60000) throw Error('Claim is too large for a PR comment; share receipt JSON as a PR attachment instead');
  console.log(api(`repos/${repository()}/issues/${envelope.receipt.pr.number}/comments`,'POST',{body}).html_url);
} else if (operation === 'collect-act') {
  clean();
  const store = path.resolve(process.argv[3] || 'build/cache/act-artifacts/1');
  const extracted = path.resolve('build/tmp/receipts/act',crypto.randomUUID());
  function extract(name,destination) {
    const directory = path.join(store,name);
    const archives = fs.readdirSync(directory).filter(file => file.endsWith('.zip'));
    if (archives.length !== 1) throw Error('Expected exactly one artifact archive');
    const archive = path.join(directory,archives[0]);
    const windows = process.platform === 'win32';
    const listing = command(windows ? 'tar' : 'unzip',windows ? ['-tf',archive] : ['-Z1',archive]).split(/\r?\n/).filter(Boolean);
    for (const file of listing) {
      const name = file.replace(/\/$/,'');
      if (!name || /[\\:\x00-\x1f]/.test(name) || name.startsWith('/') || name.split('/').some(part => !part || part === '.' || part === '..')) throw Error('Unsafe artifact archive path');
    }
    const details = command(windows ? 'tar' : 'unzip',windows ? ['-tvf',archive] : ['-Z','-l',archive]);
    if (details.split(/\r?\n/).some(line => /^[lbcps][rwx-]{9}/.test(line))) throw Error('Artifact archive contains links or special files');
    fs.mkdirSync(destination,{recursive:true});
    command(windows ? 'tar' : 'unzip',windows ? ['-xf',archive,'-C',destination] : ['-q',archive,'-d',destination]);
  }
  extract('release-plan',path.join(extracted,'plan'));
  const planFile = path.join(extracted,'plan/plan.json');
  const plan = read(planFile);
  if (plan.controller_sha !== git(['rev-parse','HEAD']) || !plan.context.local) throw Error('Act artifact store does not match this local checkout');
  for (const entry of plan.builds) {
    if (!fs.existsSync(path.join(store,entry.artifact))) continue;
    extract(entry.artifact,path.join(extracted,'distributions',entry.artifact));
    const log = `build-logs-${entry.source_sha}-${entry.name}`;
    extract(log,path.join(extracted,'logs',log));
  }
  console.log(command(process.execPath,['ci/receipts/cli.mjs','collect',planFile,path.join(extracted,'distributions'),path.join(extracted,'logs'),process.argv[4] || 'build/receipts']).trim());
} else if (operation === 'keygen') {
  const destination = path.resolve(process.argv[3] || '');
  const workspace = path.resolve('.');
  if (destination === workspace || destination.startsWith(workspace + path.sep)) throw Error('Signing key must live outside the repository');
  if (!process.argv[3] || fs.existsSync(destination)) throw Error('Supply a new private-key path outside the repository');
  const keys = crypto.generateKeyPairSync('ed25519');
  fs.mkdirSync(path.dirname(destination), {recursive:true});
  fs.writeFileSync(destination, keys.privateKey.export({type:'pkcs8',format:'pem'}), {mode:0o600,flag:'wx'});
  if (process.platform === 'win32') {
    const account = command('whoami',[]).trim();
    command('icacls',[destination,'/inheritance:r','/grant:r',account + ':F']);
  }
  console.log(JSON.stringify({ id:crypto.randomUUID(), algorithm:'ed25519', login:actor(),
    public_key:keys.publicKey.export({type:'spki',format:'pem'}), revoked:false }, null,2));
} else if (operation === 'sign') {
  if (process.env.ACT === 'true' || process.env.GITHUB_ACTIONS === 'true') throw Error('Sign outside execution environments');
  if (!isAdmin(actor())) throw Error('Admin validator required');
  const file = process.argv[3], keyId = process.argv[4], keyPath = path.resolve(process.argv[5] || '');
  if (!file || !keyId || !process.argv[5] || keyPath.startsWith(path.resolve('.') + path.sep)) throw Error('Receipt, enrolled key ID, and external private key required');
  const { receipt } = read(file);
  validate(receipt); freshPR(receipt);
  verifyBundle(path.join(path.dirname(file),'bundle'),receipt);
  if (process.argv[6]) receipt.comparison = compare(read(process.argv[6]).receipt,receipt);
  if (sha256(fs.readFileSync(path.join(path.dirname(file),policy.archive_asset))) !== receipt.bundle_sha256) throw Error('Bundle archive differs');
  write(file, sign(receipt,keyId,fs.readFileSync(keyPath)));
} else if (operation === 'submit') {
  if (process.env.ACT === 'true' || process.env.GITHUB_ACTIONS === 'true') throw Error('Submit outside execution environments; build environments do not upload validation');
  const file = process.argv[3];
  const envelope = read(file); validate(envelope.receipt); freshPR(envelope.receipt);
  if (envelope.authentication.kind !== 'signature') throw Error('Local staging requires an enrolled admin signature');
  await verifyEnvelope(envelope);
  const archive = path.join(path.dirname(file),policy.archive_asset);
  if (sha256(fs.readFileSync(archive)) !== envelope.receipt.bundle_sha256) throw Error('Bundle checksum mismatch');
  console.log(upload(envelope,archive).html_url);
} else if (operation === 'report') {
  const context = read('build/tmp/releases/plan.json').context;
  if (process.env.ACT === 'true' || process.env.GITHUB_EVENT_NAME !== 'workflow_dispatch'
    || (process.env.GITHUB_REF !== 'refs/heads/source' && !context.bootstrap) || !isAdmin(actor())) throw Error('Trusted admin source workflow required');
  const file = 'build/receipts/receipt.json';
  const envelope = read(file); freshPR(envelope.receipt);
  const differences = context.claim ? compare(JSON.parse(context.claim).receipt, envelope.receipt) : [];
  envelope.authentication = {kind:'hosted', run_id:process.env.GITHUB_RUN_ID, controller_sha:process.env.GITHUB_SHA,
    ...(context.bootstrap ? {bootstrap:true} : {})};
  envelope.receipt.comparison = differences;
  write(file,envelope);
  const release = upload(envelope,'build/receipts/bundle.tar.gz');
  write('build/receipts/acceptance.json',{release_id:release.id,differences});
  // The run artifact is the authority for this unsigned hosted envelope.
  console.log('Staged hosted validation; official check is issued after receipt artifact upload');
} else if (operation === 'accepted-check') {
  const envelope = read('build/receipts/receipt.json');
  freshPR(envelope.receipt);
  if (process.env.GITHUB_EVENT_NAME !== 'workflow_dispatch' || (process.env.GITHUB_REF !== 'refs/heads/source' && !envelope.authentication.bootstrap)
    || !isAdmin(actor())) throw Error('Trusted admin source workflow required');
  setCheck(envelope.receipt.pr.head_sha,'success',`Independent admin validation completed for ${envelope.receipt.targets.length} targets. Receipt retained in the validation-receipt run artifact.`);
} else if (operation === 'verify-pr') {
  const plan = read('build/tmp/releases/plan.json');
  const pr = currentPR(plan.context.pr.number);
  if (canonical(pr) !== canonical(plan.context.pr)) throw Error('PR changed');
  const accepted = await discover(plan,pr);
  if (accepted.length !== plan.builds.length) {
    setCheck(pr.head_sha,'failure','Admin validation required. Automatic PR validation does not schedule expensive builds.');
    throw Error('Waiting for independent admin validation');
  }
  setCheck(pr.head_sha,'success',`Verified accepted receipts for all ${accepted.length} targets, with current PR head and base.`);
} else if (operation === 'merge') {
  const number = Number(process.argv[3]);
  clean();
  const pr = currentPR(number);
  const controller = api(`repos/${repository()}/git/ref/heads/source`).object.sha;
  const checkout = git(['rev-parse','HEAD']);
  if (checkout !== controller && !(checkout === pr.head_sha && predatesContract(pr.base_sha))) throw Error('Merge from a clean trusted source controller checkout');
  const token = command('gh',['auth','token']).trim();
  git(['fetch','--no-tags','origin',pr.head_sha],{env:{...process.env,GIT_CONFIG_COUNT:'1',
    GIT_CONFIG_KEY_0:'http.https://github.com/.extraheader',GIT_CONFIG_VALUE_0:'AUTHORIZATION: basic ' + Buffer.from(`x-access-token:${token}`).toString('base64')}});
  git(['merge-base','--is-ancestor',pr.base_sha,pr.head_sha]);
  command('lune',['run','ci/releases/resolve.luau'],{env:{...process.env,ACT:'true',CI_TESTED_SHA:pr.head_sha,CI_RECEIPT_PR:String(number)}});
  const plan = read('build/tmp/releases/plan.json');
  plan.tested_sha = pr.head_sha;
  console.log(JSON.stringify(await merge(number,plan)));
} else if (operation === 'request') {
  if (process.env.ACT === 'true' || !isAdmin(actor())) throw Error('Request validation outside act as an administrator');
  const number = Number(process.argv[3] || 0);
  const pr = number ? currentPR(number) : null;
  const bootstrap = process.argv.includes('--bootstrap');
  if (bootstrap && (!pr || pr.head_sha !== git(['rev-parse','HEAD']) || !predatesContract(pr.base_sha))) throw Error('Bootstrap requires the exact first activation PR checkout');
  const claimFile = process.argv[4] && !process.argv[4].startsWith('--') ? process.argv[4] : '';
  const claim = claimFile ? JSON.stringify(read(claimFile)) : '';
  api(`repos/${repository()}/actions/workflows/ci.yml/dispatches`,'POST',{ref:bootstrap ? git(['branch','--show-current']) : 'source',inputs:{operation:'Build',target:number ? 'Pull request' : 'Source',pr:number ? String(number) : '',claim,admin:bootstrap ? 'First-time activation' : 'None'}});
  console.log('Requested independent validation using the source controller');
} else if (operation === 'check-ready') {
  const plan = read('build/tmp/releases/plan.json');
  if (!plan.context.local && !plan.context.requested && !plan.builds.every(entry => entry.accepted)) throw Error('Admin validation required; no automatic hosted fallback');
} else throw Error(`Unknown receipt operation: ${operation}`);
