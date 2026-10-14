import fs from 'node:fs';
import path from 'node:path';
import crypto from 'node:crypto';
import { canonical, command, sha256, write } from '../releases/core.mjs';
import { authenticate, applicable, executionValid, policy, unpack, verifyBundle } from './core.mjs';

export const repository = () => process.env.GITHUB_REPOSITORY || process.env.GH_REPO || command('gh', ['repo','view','--json','nameWithOwner','--jq','.nameWithOwner']).trim();
export function api(endpoint, method = 'GET', body) {
  const args = ['api', endpoint, '--method', method];
  if (body !== undefined) args.push('--input','-');
  const result = command('gh', args, body === undefined ? {} : { input: JSON.stringify(body) }).trim();
  return result ? JSON.parse(result) : null;
}
export function isAdmin(login) {
  if (!/^[a-zA-Z0-9-]+$/.test(login || '')) return false;
  return api(`repos/${repository()}/collaborators/${login}/permission`).permission === 'admin';
}
export function assertAdminWriters() {
  for (let page = 1; ; page++) {
    const users = api(`repos/${repository()}/collaborators?affiliation=all&per_page=100&page=${page}`);
    if (users.some(user => user.permissions?.push && !user.permissions?.admin)) throw Error('Non-admin repository write access violates the receipt trust boundary; use fork contributions');
    if (users.length < 100) break;
  }
}
export function actor() { return process.env.GITHUB_ACTOR || api('user').login; }
export function currentPR(number) {
  const pr = api(`repos/${repository()}/pulls/${Number(number)}`);
  if (pr.state !== 'open' || pr.base.ref !== 'source' || pr.base.repo.full_name.toLowerCase() !== repository().toLowerCase()) throw Error('Open source PR required');
  return { number: pr.number, head_sha: pr.head.sha, base_sha: pr.base.sha };
}
export function trustedKeys() {
  // Fetch the protected source ref; keys proposed in a PR do not grant trust.
  try {
    const result = api(`repos/${repository()}/contents/ci/receipts/keys.json?ref=source`);
    return JSON.parse(Buffer.from(result.content.replace(/\s/g,''), 'base64'));
  } catch (error) {
    if (String(error.stderr || error.message).includes('HTTP 404')) return {schema:1,keys:[]};
    throw error;
  }
}
export function predatesContract(sha) {
  if (!/^[a-f0-9]{40}$/.test(sha)) throw Error('Full base SHA required');
  try { api(`repos/${repository()}/contents/ci/receipts/policy.json?ref=${sha}`);return false; }
  catch (error) { if (String(error.stderr || error.message).includes('HTTP 404')) return true;throw error; }
}
async function allowBootstrap(envelope,run) {
  const receipt = envelope.receipt;
  if (receipt.pr.number < 1 || run.head_sha !== receipt.pr.head_sha || receipt.tested_sha !== run.head_sha
    || receipt.controller_sha !== run.head_sha || !predatesContract(receipt.pr.base_sha)) return false;
  const pr = api(`repos/${repository()}/pulls/${receipt.pr.number}`);
  return pr.base.ref === 'source' && pr.head.sha === run.head_sha
    && pr.head.repo.full_name.toLowerCase() === repository().toLowerCase();
}
export function listStaging() {
  const releases = [];
  for (let page = 1; ; page++) {
    const batch = api(`repos/${repository()}/releases?per_page=100&page=${page}`);
    releases.push(...batch.filter(release => release.draft && release.tag_name.startsWith(policy.staging_prefix)));
    if (batch.length < 100) break;
  }
  return releases.sort((a,b) => b.id - a.id);
}
export function download(asset, output) {
  fs.mkdirSync(path.dirname(output), { recursive: true });
  const bytes = command('gh', ['api', `repos/${repository()}/releases/assets/${asset.id}`, '-H','Accept: application/octet-stream'], { encoding: null });
  fs.writeFileSync(output, bytes);
  if (bytes.length !== asset.size || (asset.digest && asset.digest !== 'sha256:' + sha256(bytes))) throw Error('Downloaded asset checksum or size mismatch');
}
async function hostedRun(id, envelope) {
  if (!/^\d+$/.test(String(id))) throw Error('Invalid run ID');
  const run = api(`repos/${repository()}/actions/runs/${id}`);
  const root = path.resolve('build/tmp/receipts/hosted', crypto.randomUUID());
  fs.mkdirSync(root, { recursive: true });
  command('gh', ['run','download',String(id),'--repo',repository(),'--name','validation-receipt','--dir',root]);
  const original = JSON.parse(fs.readFileSync(path.join(root, 'receipt.json')));
  if (canonical(original) !== canonical(envelope)) throw Error('Hosted receipt does not match the reporting run artifact');
  return run;
}
export async function verifyEnvelope(envelope) {
  return authenticate(envelope, { repository: repository(), keys: trustedKeys(), isAdmin,
    hostedRun: id => hostedRun(id, envelope), allowBootstrap });
}
export async function discover(plan, pr = null, materialize = false) {
  const candidates = [];
  for (const release of listStaging()) {
    try {
      const asset = release.assets.find(entry => entry.name === policy.receipt_asset);
      const archive = release.assets.find(entry => entry.name === policy.archive_asset);
      if (!asset || !archive || archive.size > policy.max_archive_bytes) continue;
      const root = path.resolve('build/tmp/receipts/discovery', crypto.randomUUID());
      const file = path.join(root, 'receipt.json');
      download(asset, file);
      const envelope = JSON.parse(fs.readFileSync(file));
      const { receipt, validator } = await verifyEnvelope(envelope);
      if (receipt.controller_hash !== plan.controller_hash) continue;
      if (pr && canonical(receipt.pr) !== canonical(pr)) continue;
      const archiveFile = path.join(root, policy.archive_asset);
      download(archive, archiveFile);
      if (sha256(fs.readFileSync(archiveFile)) !== receipt.bundle_sha256) throw Error('Archive differs from signed receipt');
      const extracted = path.join(root, 'bundle');
      unpack(archiveFile, extracted); verifyBundle(extracted, receipt);
      candidates.push({ release_id: release.id, asset_id: archive.id, archive_size: archive.size,
        receipt, envelope, validator, root: extracted });
    } catch (error) { console.warn(`Rejected staging release ${release.id}: ${error.message}`); }
  }
  const accepted = [];
  for (const entry of plan.builds) {
    const match = candidates.map(candidate => ({ candidate, target: candidate.receipt.targets.find(target => applicable(target, entry) && executionValid(target, entry)) }))
      .find(match => match.target);
    if (match) {
      const { candidate, target } = match;
      entry.accepted = { release_id: candidate.release_id, asset_id: candidate.asset_id,
        archive_sha256: candidate.receipt.bundle_sha256, source_sha: target.source_sha,
        resolved_fingerprint:target.resolved_fingerprint,
        artifact: target.artifact, envelope: sha256(canonical(candidate.envelope)) };
      if (materialize) {
        fs.cpSync(path.join(candidate.root, 'distributions', target.artifact),
          path.join('build/accepted-distributions', entry.artifact), { recursive: true });
        fs.cpSync(path.join(candidate.root, 'logs', target.log_artifact),
          path.join('build/accepted-logs', `build-logs-${entry.source_sha}-${entry.name}`), { recursive: true });
      }
      accepted.push({ name: entry.name, selected_sha: entry.source_sha, tested_sha: target.source_sha,
        release_id: candidate.release_id, validator: candidate.validator });
    }
  }
  return accepted;
}
export async function restore(entry, destination) {
  const release = api(`repos/${repository()}/releases/${entry.accepted.release_id}`);
  if (!release.draft || !release.tag_name.startsWith(policy.staging_prefix)) throw Error('Staging release no longer valid');
  const root = path.resolve('build/tmp/receipts/restore', crypto.randomUUID());
  const envelopeFile = path.join(root, 'envelope.json');
  download(release.assets.find(asset => asset.name === policy.receipt_asset), envelopeFile);
  const envelope = JSON.parse(fs.readFileSync(envelopeFile));
  if (sha256(canonical(envelope)) !== entry.accepted.envelope) throw Error('Staging receipt changed');
  const { receipt } = await verifyEnvelope(envelope);
  const target = receipt.targets.find(target => applicable(target, entry) && executionValid(target, entry));
  if (!target) throw Error('Receipt no longer matches selected build');
  const asset = release.assets.find(asset => asset.id === entry.accepted.asset_id);
  if (!asset || asset.size > policy.max_archive_bytes) throw Error('Staging archive missing');
  const archive = path.join(root, policy.archive_asset);
  download(asset, archive);
  if (sha256(fs.readFileSync(archive)) !== receipt.bundle_sha256) throw Error('Staging archive changed');
  const extracted = path.join(root, 'bundle'); unpack(archive, extracted); verifyBundle(extracted, receipt);
  fs.mkdirSync(destination, { recursive: true });
  fs.cpSync(path.join(extracted, 'distributions', target.artifact), destination, { recursive: true });
  fs.mkdirSync('build/logs', {recursive:true});
  fs.cpSync(path.join(extracted,'logs',target.log_artifact),'build/logs',{recursive:true});
  return target;
}
export function upload(envelope, archive) {
  if (!isAdmin(actor())) throw Error('Only administrators may stage validation');
  if (fs.statSync(archive).size > policy.max_archive_bytes) throw Error('Validation archive exceeds staging asset limit');
  for (const expired of listStaging()) {
    if (Date.now() - Date.parse(expired.created_at) > policy.retention_days * 86400000
      && new RegExp('^' + policy.staging_prefix + '[a-f0-9-]{36}$').test(expired.tag_name)) {
      api(`repos/${repository()}/releases/${expired.id}`,'DELETE');
    }
  }
  const tag = policy.staging_prefix + crypto.randomUUID();
  const root = path.resolve('build/tmp/receipts/upload', tag);
  write(path.join(root, policy.receipt_asset), envelope);
  const archiveCopy = path.join(root, policy.archive_asset);
  fs.copyFileSync(archive, archiveCopy);
  const release = api(`repos/${repository()}/releases`, 'POST', { tag_name: tag,
    target_commitish: envelope.receipt.controller_sha, name: tag, draft: true,
    body: 'Internal validation staging. Not a channel release. Expires after 30 days.' });
  try {
    command('gh', ['release','upload',tag,path.join(root,policy.receipt_asset),archiveCopy,'--repo',repository()]);
    const refreshed = api(`repos/${repository()}/releases/${release.id}`);
    for (const name of [policy.receipt_asset,policy.archive_asset]) {
      const asset = refreshed.assets.find(asset => asset.name === name);
      if (!asset) throw Error('Uploaded asset missing');
      download(asset, path.join(root, 'verified', name));
      if (sha256(fs.readFileSync(path.join(root,'verified',name))) !== sha256(fs.readFileSync(path.join(root,name)))) throw Error('Upload verification failed');
    }
    return refreshed;
  } catch (error) {
    try { api(`repos/${repository()}/releases/${release.id}`, 'DELETE'); } catch (cleanup) { throw Error(`${error.message}; staging cleanup failed: ${cleanup.message}`); }
    throw error;
  }
}
export function setCheck(sha, conclusion, summary) {
  if (process.env.ACT === 'true') throw Error('Local execution cannot mint official checks');
  if (!process.env.GITHUB_ACTIONS || !process.env.GH_TOKEN) throw Error('Official check reporting requires trusted Actions');
  return api(`repos/${repository()}/check-runs`, 'POST', { name: 'gate', head_sha: sha,
    status: 'completed', conclusion, output: { title: conclusion === 'success' ? 'Admin validation accepted' : 'Admin validation required', summary } });
}
export function freshPR(receipt) {
  if (receipt.pr.number && canonical(currentPR(receipt.pr.number)) !== canonical(receipt.pr)) throw Error('PR head or base changed');
}
export async function merge(number, plan) {
  if (!isAdmin(actor())) throw Error('Only administrators may merge');
  const before = currentPR(number);
  if (plan.tested_sha !== before.head_sha) throw Error('Plan is not for current PR head');
  const accepted = await discover(plan, before);
  if (accepted.length !== plan.builds.length) throw Error('All required targets need current admin validation');
  const after = currentPR(number);
  if (canonical(before) !== canonical(after)) throw Error('PR changed during verification');
  command('gh', ['pr','merge',String(number),'--repo',repository(),'--merge','--match-head-commit',before.head_sha]);
  return accepted;
}
