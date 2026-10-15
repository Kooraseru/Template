import fs from 'node:fs';
import path from 'node:path';
import crypto from 'node:crypto';
import { execFileSync } from 'node:child_process';

export const policy = JSON.parse(fs.readFileSync(new URL('./policy.json', import.meta.url)));
export const sha256 = value => crypto.createHash('sha256').update(value).digest('hex');
export const canonical = value => JSON.stringify(value, (_, v) => v && !Array.isArray(v) && typeof v === 'object'
  ? Object.fromEntries(Object.keys(v).sort().map(k => [k, v[k]])) : v);
export function command(file, args, options = {}) {
  return execFileSync(file, args, { encoding: 'utf8', stdio: ['pipe', 'pipe', 'pipe'], maxBuffer: 64 * 1024 * 1024, ...options });
}
export function git(args, options) { return command('git', args, options).trimEnd(); }
export function write(file, value) {
  fs.mkdirSync(path.dirname(file), { recursive: true });
  fs.writeFileSync(file, typeof value === 'string' ? value : JSON.stringify(value, null, 2) + '\n');
}
export function normalizeArtifactDownload(root, name, marker) {
  const destination = path.join(root, relative(name));
  if (fs.existsSync(destination) || !fs.existsSync(path.join(root, marker))) return;
  const entries = fs.readdirSync(root);
  fs.mkdirSync(destination, {recursive:true});
  for (const entry of entries) fs.renameSync(path.join(root,entry),path.join(destination,entry));
}
export function relative(file) {
  if (typeof file !== 'string' || !file || /[\\:\x00-\x1f]/.test(file) || file.startsWith('/')
      || file.split('/').some(part => !part || part === '.' || part === '..')) throw Error(`Unsafe path: ${file}`);
  return file;
}
export function parseVersion(version) {
  if (typeof version !== 'string' || !/^(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)(?:-pre\.(0|[1-9][0-9]*))?$/.test(version)) {
    throw Error('Version must be MAJOR.MINOR.PATCH or MAJOR.MINOR.PATCH-pre.N without leading zeroes');
  }
  const prerelease = version.includes('-pre.');
  return { version, prerelease, type: prerelease ? 'Pre-Release' : 'Release' };
}
export function validateReleases(document, tip, repository = '.') {
  const validSHA = value => typeof value === 'string' && new RegExp(policy.sha_pattern).test(value);
  const run = args => git(args, { cwd: repository });
  const ancestor = (a, b) => { try { run(['merge-base', '--is-ancestor', a, b]); return true; } catch { return false; } };
  if (!validSHA(tip)) throw Error('Source tip must be a full SHA');
  const result = [];
  if (!document || typeof document !== 'object' || Array.isArray(document)
      || Object.keys(document).some(key => key !== 'releases')) throw Error('Expected an explicit releases list');
  let releases = document.releases;
  // Lune's JSON encoding represents an empty TOML array as an empty object.
  if (releases && !Array.isArray(releases) && typeof releases === 'object' && !Object.keys(releases).length) releases = [];
  if (!Array.isArray(releases)) throw Error('Expected a releases array');
  const seen = new Set();
  for (const selection of releases) {
    if (!selection || typeof selection !== 'object' || Array.isArray(selection)) throw Error('Invalid release selection');
    if (Object.keys(selection).some(key => !['version', 'from', 'commit', 'notes'].includes(key))) throw Error('Unknown release option');
    const version = parseVersion(selection.version);
    if (seen.has(version.version)) throw Error(`Duplicate version: ${version.version}`);
    seen.add(version.version);
    const commit = selection.commit, from = selection.from ?? 'beginning';
    if (!validSHA(commit) || !ancestor(commit, tip)) throw Error(`${version.version} commit must be a full SHA in source history`);
    if (from !== 'beginning' && (!validSHA(from) || !ancestor(from, commit))) {
      throw Error(`${version.version} range start must be an ancestor of the selected commit`);
    }
    if (selection.notes !== undefined) relative(selection.notes);
    result.push({ ...version, source_sha: commit, from, ...(selection.notes ? { notes: selection.notes } : {}) });
  }
  return result;
}
export function selectReleases(document, controls, tip, repository = '.') {
  if (Boolean(controls.release_version) !== Boolean(controls.release_commit)) throw Error('Release version and source commit must be supplied together');
  let selected = document;
  if (controls.release_version) {
    const configured = Array.isArray(document.releases) ? document.releases.find(entry => entry.version === controls.release_version) : null;
    selected = { releases: [{ ...configured, version: controls.release_version, commit: controls.release_commit }] };
  }
  let releases = validateReleases(selected, tip, repository);
  if (controls.release_output?.startsWith('Publish ')) {
    releases = releases.filter(release => controls.release_output === `Publish ${release.type}`);
    if (!releases.length) throw Error('No explicit versions match the selected public release type');
  }
  return releases;
}
export function sourceTip() {
  // Local previews resolve their checked-out source ancestry without network writes.
  if (process.env.ACT === 'true' || process.env.GITHUB_ACTIONS !== 'true') {
    if (git(['branch', '--show-current']) === 'source') return git(['rev-parse', 'HEAD']);
    try { return git(['rev-parse', 'refs/remotes/origin/source']); } catch { return git(['rev-parse', 'HEAD']); }
  }
  const ref = process.env.GH_TOKEN && process.env.GITHUB_REPOSITORY
    ? JSON.parse(command('gh', ['api', `repos/${process.env.GITHUB_REPOSITORY}/git/ref/heads/source`])).object.sha
    : git(['ls-remote', 'origin', 'refs/heads/source']).split(/\s/)[0];
  if (!new RegExp(policy.sha_pattern).test(ref)) throw Error('Cannot resolve current source tip');
  return ref;
}
export function history(selection, repository = '.', repoURL = '') {
  const run = args => git(args, { cwd: repository });
  const range = selection.from === 'beginning' ? selection.source_sha : `${selection.from}..${selection.source_sha}`;
  const commits = run(['rev-list', '--topo-order', range]).split('\n').filter(Boolean).map(sha => {
    const data = run(['show', '-s', '--format=%H%x00%P%x00%an%x00%ae%x00%aI%x00%s%x00%B', sha]).split('\0');
    return { sha: data[0], parents: data[1].split(' ').filter(Boolean), name: data[2], email: data[3],
      date: data[4], subject: data[5], body: data.slice(6).join('\0'), url: `${repoURL}/commit/${sha}` };
  });
  let context;
  if (selection.from !== 'beginning') {
    const parts = run(['show', '-s', '--format=%H%x00%P%x00%s', selection.from]).split('\0');
    context = { sha: parts[0], parents: parts[1].split(' ').filter(Boolean), subject: parts[2], context: true,
      url: `${repoURL}/commit/${parts[0]}` };
  }
  // Read mailmap from the selected source snapshot, never the mutable controller checkout.
  const mapDir = path.resolve('build/tmp/mailmap', selection.source_sha);
  fs.mkdirSync(mapDir, { recursive: true });
  const mapPath = path.join(mapDir, 'mailmap');
  let mailmap = '';
  try { mailmap = run(['show', `${selection.source_sha}:.mailmap`]); } catch { /* optional */ }
  fs.writeFileSync(mapPath, mailmap);
  const identities = [];
  const trailerIdentities = new Set();
  for (const commit of commits) {
    identities.push(`${commit.name} <${commit.email}>`);
    const trailers = command('git', ['interpret-trailers', '--parse'], { input: commit.body, cwd: repository });
    for (const line of trailers.split('\n')) {
      if (!/^co-authored-by:/i.test(line)) continue;
      const identity = line.replace(/^co-authored-by:\s*/i, '').trim();
      if (/^.+ <[^<>\s]+>$/.test(identity)) { identities.push(identity); trailerIdentities.add(identity); }
      else console.warn(`Ignoring malformed co-author trailer on ${commit.sha}`);
    }
  }
  const normalized = identities.length ? command('git', ['-c', `mailmap.file=${mapPath}`, '-c',
    'mailmap.blob=', 'check-mailmap', '--stdin'],
    { cwd: mapDir, input: identities.join('\n') + '\n', env: { ...process.env,
      GIT_DIR: run(['rev-parse', '--absolute-git-dir']) } }) : '';
  const people = new Map(), coauthors = new Map();
  const normalizedLines = normalized.split('\n').filter(Boolean);
  const coauthorLines = new Set(normalizedLines.filter((_, index) => trailerIdentities.has(identities[index])));
  for (const identity of normalized.split('\n').filter(Boolean)) {
    const match = identity.match(/^(.*) <([^<>]+)>$/);
    if (!match) continue;
    if (policy.bot_patterns.some(pattern => [identity, match[1], match[2]]
      .some(value => new RegExp(pattern, 'i').test(value)))) continue;
    people.set(match[2].toLowerCase(), match[1]);
    if (coauthorLines.has(identity)) coauthors.set(match[2].toLowerCase(), match[1]);
  }
  const refs = run(['for-each-ref', '--format=%(objectname)%09%(*objectname)%09%(refname)', 'refs/heads', 'refs/remotes', 'refs/tags']);
  const labels = new Map();
  for (const line of refs.split('\n')) {
    const [object, peeled, reference] = line.split('\t');
    const sha = peeled || object;
    if (!sha || !reference || reference.endsWith('/HEAD')) continue;
    const name = reference.replace(/^refs\/(heads|remotes|tags)\//, '');
    if (!labels.has(sha)) labels.set(sha, []);
    labels.get(sha).push(name);
  }
  for (const row of [...commits, ...(context ? [context] : [])]) row.refs = labels.get(row.sha) || [];
  const emptyTree = run(['hash-object', '-t', 'tree', '--stdin']);
  const stats = run(['diff', '--stat', selection.from === 'beginning' ? emptyTree : selection.from, selection.source_sha]);
  const shortstat = run(['diff', '--shortstat', selection.from === 'beginning' ? emptyTree : selection.from, selection.source_sha]).trim();
  return { commits, context, coauthors: [...coauthors.values()].sort((a, b) => a.localeCompare(b)), contributors: [...people.values()].sort((a, b) => a.localeCompare(b)), stats, shortstat };
}
export function layout(rows) {
  const lanes = [];
  return rows.map(row => {
    let lane = lanes.indexOf(row.sha);
    const incoming = lane !== -1;
    if (lane === -1) { lane = lanes.indexOf(null); if (lane === -1) lane = lanes.length; lanes[lane] = row.sha; }
    const before = [...lanes];
    lanes[lane] = null;
    const edges = [];
    for (const [index, parent] of row.parents.entries()) {
      let destination = lanes.indexOf(parent);
      if (destination === -1) {
        destination = index === 0 && lanes[lane] === null ? lane : lanes.indexOf(null);
        if (destination === -1) destination = lanes.length;
        lanes[destination] = parent;
      }
      edges.push({ from: lane, to: destination, parent });
    }
    const after = [...lanes];
    while (lanes.at(-1) === null) lanes.pop();
    return { ...row, lane, incoming, before, after, edges };
  });
}
export const escapeHTML = value => String(value).replace(/[&<>"']/g, char => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[char]));
export const escapeMarkdown = value => String(value).replace(/[\\`*_{}\[\]()<>#!|]/g, '\\$&').replace(/[\r\n]/g, ' ');
export function verifyDistribution(root, expected) {
  const metadata = JSON.parse(fs.readFileSync(path.join(root, 'provenance.json')));
  if (metadata.schema !== 1 || metadata.source_sha !== (expected.accepted?.source_sha || expected.accepted_source_sha || expected.source_sha)
      || metadata.fingerprint !== expected.fingerprint || metadata.target !== expected.name) throw Error('Distribution provenance mismatch');
  if (expected.accepted?.resolved_fingerprint && metadata.resolved_fingerprint !== expected.accepted.resolved_fingerprint) throw Error('Resolved build environment mismatch');
  const manifest = JSON.parse(fs.readFileSync(path.join(root, 'manifest.json')));
  if (!Array.isArray(manifest) || !manifest.some(entry => entry.path === 'provenance.json')
      || !manifest.some(entry => entry.path === 'distribution.tar.gz')) throw Error('Incomplete distribution manifest');
  const seen = new Set();
  for (const entry of manifest) {
    relative(entry.path);
    if (seen.has(entry.path) || !/^[a-f0-9]{64}$/.test(entry.sha256)) throw Error('Invalid distribution manifest');
    seen.add(entry.path);
    const file = path.join(root, entry.path);
    if (!fs.lstatSync(file).isFile() || sha256(fs.readFileSync(file)) !== entry.sha256) throw Error(`Distribution checksum mismatch: ${entry.path}`);
  }
  function inspect(dir, prefix = '') {
    for (const entry of fs.readdirSync(dir, { withFileTypes: true })) {
      const name = prefix + entry.name;
      if (entry.isDirectory()) inspect(path.join(dir, entry.name), name + '/');
      else if (!entry.isFile() || (name !== 'manifest.json' && !seen.has(name))) throw Error(`Unlisted artifact: ${name}`);
    }
  }
  inspect(root);
  return { metadata, manifest };
}
export function cacheEligible(run, sha, repository) {
  return run.event === 'push' && run.head_branch === 'source' && run.head_sha === sha
    && run.conclusion === 'success' && run.head_repository?.full_name?.toLowerCase() === repository.toLowerCase();
}
export function artifactEligible(artifact, name) {
  return artifact.name === name && artifact.expired === false;
}
export function protectionsValid(rulesets) {
  const applicable = rulesets.filter(set => set.enforcement === 'active' && set.target === 'branch'
    && set.conditions?.ref_name?.include?.some(ref => ['refs/heads/source', '~DEFAULT_BRANCH', '~ALL'].includes(ref))
    && !(set.conditions?.ref_name?.exclude || []).some(ref => ['refs/heads/source', '~ALL', '~DEFAULT_BRANCH'].includes(ref)));
  const adminOnly = actors => Array.isArray(actors) && actors.every(actor => actor.actor_type === 'RepositoryRole'
    && actor.actor_id === 5 && ['pull_request', 'always'].includes(actor.bypass_mode));
  const checks = applicable.some(set => adminOnly(set.bypass_actors)
    && ['pull_request', 'non_fast_forward', 'deletion'].every(type => set.rules.some(rule => rule.type === type))
    && set.rules.some(rule => rule.type === 'required_status_checks' && rule.parameters.strict_required_status_checks_policy
      && rule.parameters.required_status_checks.some(check => check.context === 'gate' && check.integration_id === 15368)));
  const restricted = applicable.some(set => set.rules.some(rule => rule.type === 'update')
    && set.bypass_actors?.length === 1 && adminOnly(set.bypass_actors));
  return checks && restricted;
}
export function verifiedProtections(live, attestation, repository) {
  if (live.every(set => Array.isArray(set.bypass_actors))) return live;
  if (attestation?.schema !== 1 || attestation.repository !== repository
    || !Array.isArray(attestation.rulesets) || !protectionsValid(attestation.rulesets)
    || attestation.rulesets.length !== live.length) throw Error('Admin source-protection attestation required');
  const visible = set => ({id:set.id, name:set.name, target:set.target, source_type:set.source_type,
    source:set.source, enforcement:set.enforcement, conditions:set.conditions, rules:set.rules,
    updated_at:new Date(set.updated_at).toISOString()});
  return live.map(set => {
    const enrolled = attestation.rulesets.find(candidate => candidate.id === set.id);
    if (!enrolled || canonical(visible(set)) !== canonical(visible(enrolled))) throw Error('Source protection changed; refresh admin attestation');
    return {...set,bypass_actors:enrolled.bypass_actors};
  });
}
