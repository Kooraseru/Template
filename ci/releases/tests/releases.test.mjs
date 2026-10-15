import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import assert from 'node:assert/strict';
import test from 'node:test';
import { command, git, write, sha256, validateReleases, selectReleases, parseVersion, history, layout, verifyDistribution, cacheEligible, artifactEligible, protectionsValid, verifiedProtections } from '../core.mjs';
import { svg, htmlGraph, finalizeAssets, packageArchive, assemble } from '../render.mjs';
import { publish, client } from '../publish.mjs';

const cases = JSON.parse(fs.readFileSync(new URL('./cases.json', import.meta.url)));
const root = path.resolve('build/tests/releases');
fs.rmSync(root, { recursive: true, force: true });
fs.mkdirSync(root, { recursive: true });
const repository = path.join(root, 'history');
fs.mkdirSync(repository);
git(['init', '--initial-branch=source', repository]);
const run = (args, options = {}) => git(args, { cwd: repository, ...options });
run(['config', 'user.name', 'Test Committer']); run(['config', 'user.email', 'committer@example.test']);
const commits = {};
for (const entry of cases.history.commits) {
  if (entry.parent) run(['checkout', '-B', entry.branch, commits[entry.parent]]);
  else if (Object.keys(commits).length) run(['checkout', entry.branch]);
  const env = { ...process.env, GIT_AUTHOR_NAME: entry.name, GIT_AUTHOR_EMAIL: entry.email };
  if (entry.merge) run(['merge', '--no-ff', '--no-commit', commits[entry.merge]]);
  if (entry.mailmap) write(path.join(repository, '.mailmap'), entry.mailmap);
  write(path.join(repository, entry.id + '.txt'), entry.message);
  for (const [name, contents] of Object.entries(entry.files || {})) write(path.join(repository, name), contents);
  run(['add', '.']); run(['commit', '-m', entry.message], { env });
  commits[entry.id] = run(['rev-parse', 'HEAD']);
}
const expand = value => JSON.parse(JSON.stringify(value).replace(/\$(root|feature|main|merge)/g, (_, key) => commits[key]));
for (const scenario of cases.snapshots) test(scenario.name, () => {
  const sourceSHA = expand(scenario.commit);
  const spec = { name: 'fixture', source_sha: sourceSHA, fingerprint: sha256('fixture'), cache_run: '' };
  command(process.execPath, [fileURLToPath(new URL('../cli.mjs', import.meta.url)), 'prepare'], {
    cwd: repository, env: { ...process.env, CI_BUILD_SPEC: JSON.stringify(spec), GITHUB_OUTPUT: '' },
  });
  const source = path.join(repository, 'build/tmp/source', sourceSHA);
  assert.equal(git(['rev-parse', 'HEAD'], { cwd: source }), sourceSHA);
  assert.ok(!fs.existsSync(path.join(source, '.git/objects/info/alternates')));
  for (const name of scenario.present) assert.ok(fs.existsSync(path.join(source, name)));
  for (const name of scenario.absent) assert.ok(!fs.existsSync(path.join(source, name)));
});
test('native programs execute from the selected checkout', () => {
  const source = path.join(root, 'native-checkout');
  fs.mkdirSync(path.join(source, 'build'), { recursive: true });
  const name = process.platform === 'win32' ? 'source-node.exe' : 'source-node';
  fs.copyFileSync(process.execPath, path.join(source, 'build', name));
  fs.chmodSync(path.join(source, 'build', name), 0o755);
  command('lune', ['run', 'ci/build/tests/native-execute.luau'], {
    env: { ...process.env, CI_SOURCE_DIR: source, CI_BUILD_SPEC: '' },
  });
});
for (const scenario of cases.releases) test(scenario.name, () => {
  const execute = () => validateReleases(expand(scenario.input), commits.merge, repository);
  if (scenario.valid) assert.ok(execute().length); else assert.throws(execute);
});

test('only the two permitted SemVer forms are accepted', () => {
  for (const version of ['0.1.0', '1.2.0', '12.34.56', '1.3.0-pre.0', '1.3.0-pre.1', '1.3.0-pre.10']) {
    assert.equal(parseVersion(version).prerelease, version.includes('-pre.'));
  }
  for (const version of ['1.2', 'v1.2.0', '01.2.0', '1.02.0', '1.2.00', '1.2.0-pre.01',
    '1.2.0-beta.1', '1.2.0-rc.1', '1.2.0-pre', '1.2.0+build.1', 'Release', '../1.2.0']) {
    assert.throws(() => parseVersion(version));
  }
});

test('an empty explicit version list selects no public release', () => {
  assert.deepEqual(validateReleases({ releases: [] }, commits.merge, repository), []);
  assert.deepEqual(validateReleases({ releases: {} }, commits.merge, repository), []);
  assert.throws(() => validateReleases({}, commits.merge, repository));
});

test('manual version selection is explicit and public types are derived from the version', () => {
  const document = { releases: [{ version: '1.2.0', commit: commits.merge, from: commits.root },
    { version: '1.3.0-pre.1', commit: commits.merge }] };
  const selected = selectReleases(document, { release_output: 'Publish Pre-Release' }, commits.merge, repository);
  assert.equal(selected.length, 1); assert.equal(selected[0].version, '1.3.0-pre.1');
  const override = selectReleases(document, { release_version: '1.2.0', release_commit: commits.merge }, commits.merge, repository);
  assert.equal(override[0].from, commits.root, 'manual selection preserves configured release-note ranges');
  const promoted = selectReleases({ releases: [] }, { release_version: '1.3.0', release_commit: commits.merge }, commits.merge, repository);
  assert.equal(promoted[0].type, 'Release');
  assert.equal(document.releases.length, 2, 'selection must not mutate configuration');
  assert.throws(() => selectReleases(document, { release_version: '1.2.0' }, commits.merge, repository));
  assert.throws(() => selectReleases({ releases: [] }, { release_output: 'Publish Release' }, commits.merge, repository));
});

test('public assembly is stable across internal receipt restaging', async () => {
  const file = `build/distributions/distribution-${commits.merge}-fixture`;
  const fingerprint = sha256('assembly fixture');
  const provenance = { schema: 1, source_sha: commits.merge, fingerprint, target: 'fixture' };
  write(`${file}/provenance.json`, provenance); write(`${file}/distribution.tar.gz`, 'payload');
  write(`${file}/manifest.json`, ['provenance.json', 'distribution.tar.gz'].map(name => ({ path: name,
    sha256: sha256(fs.readFileSync(`${file}/${name}`)) })));
  const selection = validateReleases({ releases: [{ version: '1.2.0', commit: commits.merge }] }, commits.merge, repository)[0];
  const plan = { controller_sha: 'a'.repeat(40), controller_hash: 'b'.repeat(64), selections: [selection], builds: [{
    name: 'fixture', source_sha: commits.merge, artifact: path.basename(file), fingerprint, accepted: { release_id: 1 },
  }] };
  const previousRepo = process.env.GITHUB_REPOSITORY;
  process.env.GITHUB_REPOSITORY = 'example/project';
  // History belongs to the isolated fixture repository; assembly otherwise uses
  // the caller's working directory. Supply that history through the Git wrapper.
  const previousGit = process.env.GIT_DIR, previousWorkTree = process.env.GIT_WORK_TREE;
  process.env.GIT_DIR = path.join(repository, '.git'); process.env.GIT_WORK_TREE = repository;
  const options = { render: dir => {
    for (const name of fs.readdirSync(dir).filter(name => name.endsWith('.svg'))) write(`${dir}/${name.replace('.svg', '.png')}`, 'PNG fixture');
  }, archive: dir => write(`${dir}/packages.tar.gz`, 'deterministic package fixture') };
  try {
    await assemble(plan, options);
    const before = fs.readFileSync('build/releases/1.2.0/release.json');
    assert.ok(!before.includes(Buffer.from('release_id')));
    plan.controller_sha = 'c'.repeat(40); plan.builds[0].accepted.release_id = 2;
    await assemble(plan, options);
    assert.deepEqual(fs.readFileSync('build/releases/1.2.0/release.json'), before);
    assert.equal(JSON.parse(fs.readFileSync('build/releases/1.2.0/publication.json')).targets[0].contract.accepted.release_id, 2);
  } finally {
    for (const [key, value] of Object.entries({ GITHUB_REPOSITORY: previousRepo, GIT_DIR: previousGit, GIT_WORK_TREE: previousWorkTree })) {
      if (value === undefined) delete process.env[key]; else process.env[key] = value;
    }
  }
});

test('release archives normalize filesystem timestamps', { skip: process.platform === 'win32' }, () => {
  const directory = path.join(root, 'archive');
  write(`${directory}/packages/fixture.txt`, 'stable content');
  packageArchive(directory); const before = fs.readFileSync(`${directory}/packages.tar.gz`);
  fs.utimesSync(`${directory}/packages/fixture.txt`, new Date(100000), new Date(100000));
  packageArchive(directory);
  assert.deepEqual(fs.readFileSync(`${directory}/packages.tar.gz`), before);
});
test('range, merge topology, mailmap and co-author credits', () => {
  const selection = { from: commits.root, source_sha: commits.merge };
  const data = history(selection, repository, 'https://github.com/example/project');
  assert.equal(data.commits.length, cases.history.range_count);
  assert.deepEqual(data.contributors, cases.history.contributors);
  assert.equal(data.context.sha, commits.root);
  const rows = layout([...data.commits, data.context]);
  assert.ok(rows.some(row => row.edges.length === 2));
  assert.ok(svg(rows).includes('&lt;safe&gt;'));
  assert.ok(!htmlGraph(rows, '1.0.0-pre.1', commits.merge).includes('<script'));
  assert.equal(history({ from: 'beginning', source_sha: commits.merge }, repository).commits.length, cases.history.beginning_count);
  assert.equal(history({ from: commits.root, source_sha: commits.root }, repository).contributors.length, 0);
});
test('release metadata names match linked assets and final checksums', () => {
  const dir = path.join(root, 'asset-names');
  const metadata = { schema: 2, version: '1.0.0-pre.1', prerelease: true, type: 'Pre-Release', source_sha: commits.merge, targets: [] };
  write(`${dir}/notes.md`, `![Graph](https://github.com/example/project/releases/download/1.0.0-pre.1/1.0.0-pre.1-graph-001.png)`);
  write(`${dir}/graph-001.png`, 'graph');
  const result = finalizeAssets(dir, metadata, ['notes.md', 'graph-001.png']);
  const notes = fs.readFileSync(`${dir}/notes.md`, 'utf8');
  for (const asset of result.assets) assert.equal(asset.sha256, sha256(fs.readFileSync(`${dir}/${asset.path}`)));
  assert.ok(notes.includes('/' + result.assets.find(asset => asset.path === 'graph-001.png').name + ')'));
  assert.equal(JSON.parse(fs.readFileSync(`${dir}/release.json`)).version, result.version);
});
for (const scenario of cases.cache) test(scenario.name, () => {
  const run = { event: 'push', head_branch: 'source', head_sha: commits.merge, conclusion: 'success', head_repository: { full_name: 'example/project' } };
  assert.equal(cacheEligible({ ...run, ...scenario.patch }, commits.merge, 'example/project'), scenario.valid);
});
for (const scenario of cases.artifacts) test(scenario.name, () => {
  assert.equal(artifactEligible(scenario.input, 'distribution-selected-linux'), scenario.valid);
});
for (const [index, scenario] of cases.provenance.entries()) test(scenario.name, () => {
  const dir = path.join(root, 'provenance', String(index));
  const expected = { name: 'linux', source_sha: commits.merge, fingerprint: sha256('inputs') };
  const metadata = { schema: 1, source_sha: expected.source_sha, fingerprint: expected.fingerprint, target: expected.name, ...scenario.patch };
  write(`${dir}/provenance.json`, metadata); write(`${dir}/distribution.tar.gz`, 'payload');
  write(`${dir}/manifest.json`, ['provenance.json', 'distribution.tar.gz'].map(file => ({ path: file, sha256: sha256(fs.readFileSync(`${dir}/${file}`)) })));
  if (scenario.corrupt) write(`${dir}/distribution.tar.gz`, 'corrupted');
  if (scenario.extra) write(`${dir}/secret.txt`, 'unlisted');
  if (scenario.valid) assert.ok(verifyDistribution(dir, expected)); else assert.throws(() => verifyDistribution(dir, expected));
});
test('source rules permit administrator overrides and reject non-admin bypass', () => {
  const sets = ['source-checks', 'source-admins'].map(name => JSON.parse(fs.readFileSync(`ci/releases/protection/${name}.json`)));
  assert.equal(protectionsValid(sets), true);
  assert.equal(protectionsValid([sets[0]]), false);
  const adminOverride = structuredClone(sets);
  for (const set of adminOverride) set.bypass_actors = [{ actor_id: 5, actor_type: 'RepositoryRole', bypass_mode: 'always' }];
  assert.equal(protectionsValid(adminOverride), true);
  const unsafe = structuredClone(adminOverride); unsafe[0].bypass_actors[0].actor_id = 4;
  assert.equal(protectionsValid(unsafe), false);
  const appBypass = structuredClone(adminOverride); appBypass[0].bypass_actors[0].actor_type = 'Integration';
  assert.equal(protectionsValid(appBypass), false);
  const unsafeUpdates = structuredClone(adminOverride); unsafeUpdates[1].bypass_actors[0].actor_id = 4;
  assert.equal(protectionsValid(unsafeUpdates), false);
});
for (const scenario of cases.protection_visibility) test(scenario.name, () => {
  const rulesets = ['source-checks','source-admins'].map((name,index) => ({
    ...JSON.parse(fs.readFileSync(`ci/releases/protection/${name}.json`)),
    id:index+1,updated_at:'2026-10-14T00:00:00Z'
  }));
  const live = structuredClone(rulesets);
  for (const set of live) delete set.bypass_actors;
  if (scenario.changed_time) live[0].updated_at = '2026-10-14T01:00:00Z';
  if (scenario.changed_rules) live[0].rules = [];
  if (scenario.unsafe) rulesets[0].bypass_actors = [{actor_id:4,actor_type:'RepositoryRole',bypass_mode:'always'}];
  const snapshot = scenario.missing ? null : {schema:1,repository:scenario.wrong_repository?'other/repository':'owner/project',rulesets};
  const verify = () => assert.equal(protectionsValid(verifiedProtections(live,snapshot,'owner/project')),true);
  if (scenario.valid) verify(); else assert.throws(verify);
});
test('local publication is denied before network access', async () => {
  const previous = process.env.ACT;
  process.env.ACT = 'true';
  try { await assert.rejects(() => publish('1.0.0-pre.1'), /Local or untrusted/); }
  finally { if (previous === undefined) delete process.env.ACT; else process.env.ACT = previous; }
});
test('temporary GET failures retry', async () => {
  let requests = 0;
  const api = client('test', 'example/project', async () => ++requests === 1
    ? new Response('unavailable', { status: 503 }) : new Response('{"ok":true}', { status: 200 }));
  assert.deepEqual(await api.request('/test'), { ok: true }); assert.equal(requests, 2);
});

test('GitHub client can verify asset bytes without forwarding internal request options', async () => {
  const bytes = Buffer.from('binary asset');
  const api = client('test', 'example/project', async (url, options) => {
    assert.equal(options.binary, undefined);
    assert.equal(options.missing, undefined);
    return new Response(bytes, { status: 200 });
  });
  assert.deepEqual(await api.request('/releases/assets/1', { binary: true, missing: true }), bytes);
});
