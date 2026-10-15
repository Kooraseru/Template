import fs from 'node:fs';
import path from 'node:path';
import crypto from 'node:crypto';
import { canonical, command, git, relative, sha256, verifyDistribution, normalizeArtifactDownload } from '../releases/core.mjs';

export const policy = JSON.parse(fs.readFileSync(new URL('./policy.json', import.meta.url)));
const shaPattern = /^[a-f0-9]{40}$/;
const digestPattern = /^[a-f0-9]{64}$/;
const identities = new Map();
export function identity(sha, cwd = '.') {
  if (!shaPattern.test(sha)) throw Error('Full source SHA required');
  const key = path.resolve(cwd) + ':' + sha;
  if (identities.has(key)) return identities.get(key);
  const files = git(['ls-tree', '-r', '-z', sha], { cwd }).split('\0').filter(Boolean).map(line => {
    const tab = line.indexOf('\t');
    const [mode, type, oid] = line.slice(0, tab).split(' ');
    const name = relative(line.slice(tab + 1));
    if (type !== 'blob') throw Error('Submodules require explicit immutable input support');
    const bytes = command('git', ['cat-file', 'blob', oid], { cwd, encoding: null });
    return { path: name, mode, sha256: sha256(bytes) };
  });
  const result = { source_sha: sha, tree: git(['rev-parse', `${sha}^{tree}`], { cwd }),
    source_manifest_sha256: sha256(canonical(files)), files };
  identities.set(key,result);
  return result;
}
export function clean(cwd = '.') {
  if (git(['status', '--porcelain', '--untracked-files=all'], { cwd })) throw Error('Committed clean checkout required');
}
export function manifest(root) {
  const files = [];
  function walk(dir, prefix = '') {
    for (const entry of fs.readdirSync(dir, { withFileTypes: true }).sort((a,b) => a.name.localeCompare(b.name))) {
      const name = relative(prefix + entry.name);
      if (entry.isSymbolicLink()) throw Error('Bundle symlinks are forbidden');
      if (entry.isDirectory()) walk(path.join(dir, entry.name), name + '/');
      else if (entry.isFile()) files.push({ path: name, sha256: sha256(fs.readFileSync(path.join(root, name))) });
      else throw Error('Unsupported bundle file');
    }
  }
  walk(root);
  return files.sort((a,b) => a.path.localeCompare(b.path));
}
export function verifyFiles(root, files) {
  if (!Array.isArray(files)) throw Error('Invalid file manifest');
  const actual = manifest(root);
  if (canonical(actual) !== canonical([...files].sort((a,b) => a.path.localeCompare(b.path)))) throw Error('Bundle files or checksums differ');
}
export function validate(receipt, now = Date.now()) {
  for (const field of policy.required_receipt_fields) if (!(field in receipt)) throw Error(`Missing receipt field ${field}`);
  if (receipt.schema !== policy.schema || !/^[^/\s]+\/[^/\s]+$/.test(receipt.repository)
    || !shaPattern.test(receipt.tested_sha) || !shaPattern.test(receipt.tree)
    || !digestPattern.test(receipt.source_manifest_sha256) || !digestPattern.test(receipt.controller_hash)) throw Error('Invalid receipt identity');
  const age = now - Date.parse(receipt.created_at);
  if (!Number.isFinite(age) || age < -300000 || age > policy.retention_days * 86400000) throw Error('Expired or future receipt');
  if (!receipt.pr || !Number.isInteger(receipt.pr.number) || receipt.pr.number < 0
    || !shaPattern.test(receipt.pr.head_sha) || !shaPattern.test(receipt.pr.base_sha)) throw Error('Invalid PR identity');
  if (!Array.isArray(receipt.targets) || !receipt.targets.length) throw Error('No target coverage');
  const seen = new Set();
  for (const target of receipt.targets) {
    for (const field of policy.required_target_fields) if (!(field in target)) throw Error(`Missing target field ${field}`);
    if (!/^[a-z0-9][a-z0-9-]*$/.test(target.name) || seen.has(target.name + ':' + target.source_sha)
      || !shaPattern.test(target.source_sha) || !shaPattern.test(target.tree)
      || !digestPattern.test(target.source_manifest_sha256) || !digestPattern.test(target.fingerprint)
      || target.resolved_fingerprint !== sha256(canonical({inputs:target.fingerprint,execution:target.execution}))
      || !policy.reuse_identities.includes(target.reuse_identity) || target.result !== 'success') throw Error('Invalid or failed target');
    seen.add(target.name + ':' + target.source_sha);
    if (!Array.isArray(target.files) || !Array.isArray(target.logs) || !target.logs.length) throw Error('Files and execution logs required');
    if (!target.execution || !['native', 'container'].includes(target.execution.kind)
      || !['linux','win32','darwin'].includes(target.execution.os) || !['x64','arm64'].includes(target.execution.arch)) throw Error('Invalid execution platform');
    for (const file of [...target.files, ...target.logs]) {
      relative(file.path);
      if (!digestPattern.test(file.sha256)) throw Error('Invalid file checksum');
    }
    if (!policy.required_bundle_files.every(name => target.files.some(file => file.path === name))) throw Error('Incomplete target distribution');
  }
  return receipt;
}
export function sign(receipt, keyId, privateKey) {
  validate(receipt);
  return { receipt, authentication: { kind: 'signature', key_id: keyId,
    signature: crypto.sign(null, Buffer.from(canonical(receipt)), privateKey).toString('base64') } };
}
export async function authenticate(envelope, { keys, isAdmin, hostedRun, repository, allowBootstrap, allowPendingRun, allowDiagnostic }, now = Date.now()) {
  const receipt = validate(envelope.receipt, now);
  if (receipt.diagnostic && !(allowDiagnostic && await allowDiagnostic(receipt))) {
    throw Error('Diagnostic results cannot become accepted validation');
  }
  if (receipt.repository.toLowerCase() !== repository.toLowerCase()) throw Error('Wrong repository');
  const auth = envelope.authentication;
  if (auth?.kind === 'signature') {
    const key = keys.keys.find(entry => entry.id === auth.key_id && !entry.revoked);
    if (!key || key.algorithm !== 'ed25519' || !await isAdmin(key.login)
      || !crypto.verify(null, Buffer.from(canonical(receipt)), key.public_key, Buffer.from(auth.signature, 'base64'))) throw Error('Untrusted signature or validator');
    return { receipt, validator: key.login };
  }
  if (auth?.kind === 'hosted' && hostedRun) {
    const run = await hostedRun(auth.run_id);
    const bootstrap = auth.bootstrap === true && allowBootstrap && await allowBootstrap(envelope,run);
    if (run.event !== 'workflow_dispatch' || (run.head_branch !== 'source' && !bootstrap)
      || run.head_sha !== auth.controller_sha || (run.conclusion !== 'success' && !(allowPendingRun && await allowPendingRun(run)))
      || run.head_repository?.full_name?.toLowerCase() !== repository.toLowerCase()
      || run.path !== '.github/workflows/ci.yml' || !await isAdmin(run.actor.login)) throw Error('Untrusted hosted validation');
    return { receipt, validator: run.actor.login };
  }
  throw Error('Contributor claim is not accepted validation');
}
export function applicable(target, entry) {
  return target.name === entry.name && target.result === 'success' && target.fingerprint === entry.fingerprint
    && target.reuse_identity === entry.reuse_identity
    && (entry.reuse_identity === 'source_tree'
      ? target.tree === entry.tree && target.source_manifest_sha256 === entry.source_manifest_sha256
      : target.source_sha === entry.source_sha && target.tree === entry.tree && target.source_manifest_sha256 === entry.source_manifest_sha256);
}
export function executionValid(target, entry) {
  const prefix = Object.keys(policy.native_runners).find(name => entry.runner.startsWith(name)
    || entry.name?.startsWith(name + '-'));
  if (!prefix) return target.execution.os === 'linux' && (!entry.platform
    || target.execution.arch === (entry.platform.endsWith('arm64') ? 'arm64' : 'x64'));
  const arch = /arm64|aarch64/.test(entry.target || entry.name) ? 'arm64' : 'x64';
  return target.execution.kind === 'native' && target.execution.os === policy.native_runners[prefix] && target.execution.arch === arch;
}
export function compare(claim, accepted) {
  validate(claim); validate(accepted);
  if (claim.repository !== accepted.repository || claim.tested_sha !== accepted.tested_sha
    || claim.controller_hash !== accepted.controller_hash || canonical(claim.pr) !== canonical(accepted.pr)) throw Error('Claim inputs differ');
  const differences = [];
  for (const other of claim.targets) {
    const target = accepted.targets.find(entry => entry.name === other.name && entry.source_sha === other.source_sha);
    if (!target || other.fingerprint !== target.fingerprint || other.tree !== target.tree
      || other.source_manifest_sha256 !== target.source_manifest_sha256 || other.result !== target.result
      || other.resolved_fingerprint !== target.resolved_fingerprint) throw Error('Claim target inputs, resolved environment, or outcomes differ');
    if (canonical(other.files) !== canonical(target.files)) {
      if (target.reproducible === true) throw Error(`Reproducible output mismatch: ${target.name}`);
      differences.push({ target: target.name, reason: 'non-reproducible output checksums differ' });
    }
  }
  return differences;
}
export function collect(plan, distributions, logs, context) {
  clean();
  if (plan.builds.length === 1) {
    normalizeArtifactDownload(distributions, plan.builds[0].artifact, 'provenance.json');
    const marker = fs.existsSync(logs) ? fs.readdirSync(logs).find(name => name.endsWith('.log')) : null;
    if (marker) normalizeArtifactDownload(logs, `build-logs-${plan.builds[0].source_sha}-${plan.builds[0].name}`, marker);
  }
  const source = identity(context.tested_sha || plan.controller_sha);
  const targets = plan.builds.map(entry => {
    const root = path.join(distributions, entry.artifact);
    if (!fs.existsSync(root) && context.local) return null;
    const verified = verifyDistribution(root, entry);
    const execution = verified.metadata.execution;
    if (!execution) throw Error(`Execution evidence missing: ${entry.name}`);
    const selected = identity(verified.metadata.source_sha);
    const logRoot = path.join(logs, `build-logs-${entry.source_sha}-${entry.name}`);
    if (!fs.existsSync(logRoot) || !manifest(logRoot).length) throw Error(`Logs missing: ${entry.name}`);
    return { name: entry.name, ...selected, files: manifest(root), logs: manifest(logRoot),
      fingerprint: entry.fingerprint, reuse_identity: entry.reuse_identity,
      resolved_fingerprint:verified.metadata.resolved_fingerprint,
      reproducible: entry.reproducible === true, result: 'success', execution,
      artifact: entry.artifact, log_artifact: path.basename(logRoot) };
  }).filter(Boolean);
  const receipt = { schema: policy.schema, repository: context.repository, tested_sha: source.source_sha,
    tree: source.tree, source_manifest_sha256: source.source_manifest_sha256, controller_hash: plan.controller_hash,
    controller_sha: plan.controller_sha, created_at: new Date().toISOString(), pr: context.pr, targets,
    required_targets:plan.builds.map(entry => ({name:entry.name,source_sha:entry.source_sha})),
    diagnostic: context.diagnostic === true || plan.validation?.success === false,
    validation_scope: context.controls?.validation_scope || 'All',
    controls: context.controls, partial:targets.length !== plan.builds.length };
  return validate(receipt);
}
export function bundle(root, receipt, distributions, logs) {
  fs.mkdirSync(root, { recursive: true });
  for (const target of receipt.targets) {
    fs.cpSync(path.join(distributions, target.artifact), path.join(root, 'distributions', target.artifact), { recursive: true });
    fs.cpSync(path.join(logs, target.log_artifact), path.join(root, 'logs', target.log_artifact), { recursive: true });
  }
}
export function verifyBundle(root, receipt) {
  validate(receipt);
  const expected = [];
  for (const target of receipt.targets) {
    const verified = verifyDistribution(path.join(root,'distributions',relative(target.artifact)),
      {source_sha:target.source_sha,fingerprint:target.fingerprint,name:target.name});
    if (verified.metadata.tree !== target.tree || verified.metadata.source_manifest_sha256 !== target.source_manifest_sha256
      || verified.metadata.resolved_fingerprint !== target.resolved_fingerprint
      || canonical(verified.metadata.execution) !== canonical(target.execution)) throw Error('Distribution execution evidence differs from receipt');
    for (const probe of target.execution.probe_logs || []) {
      if (!target.logs.some(file => file.path === probe.path && file.sha256 === probe.sha256)) throw Error('Toolchain probe evidence missing');
    }
    verifyFiles(path.join(root, 'distributions', relative(target.artifact)), target.files);
    verifyFiles(path.join(root, 'logs', relative(target.log_artifact)), target.logs);
    for (const [prefix, files] of [[`distributions/${target.artifact}/`, target.files], [`logs/${target.log_artifact}/`, target.logs]]) {
      expected.push(...files.map(file => ({ path: prefix + file.path, sha256: file.sha256 })));
    }
  }
  verifyFiles(root, expected);
}
export function unpack(archive, root) {
  const names = command('tar', ['-tzf', archive]).split(/\r?\n/).filter(Boolean);
  for (const name of names) if (name !== './') relative(name.replace(/^\.\//, '').replace(/\/$/, ''));
  const listing = command('tar', ['-tvzf', archive]).split(/\r?\n/).filter(Boolean);
  if (listing.some(line => !['-','d'].includes(line[0]))) throw Error('Archive links or special files forbidden');
  if (fs.existsSync(root)) throw Error('Extraction destination must be fresh');
  fs.mkdirSync(root, { recursive: true });
  command('tar', ['-xzf', archive, '-C', root]);
}
