import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import assert from 'node:assert/strict';
import test from 'node:test';
import { command, git, write, sha256, validateChannels, history, layout, verifyDistribution, cacheEligible, artifactEligible, protectionsValid } from '../core.mjs';
import { svg, htmlGraph, finalizeAssets } from '../render.mjs';
import { updateChannel, publish, client } from '../publish.mjs';

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
for (const scenario of cases.channels) test(scenario.name, () => {
  const execute = () => validateChannels(expand(scenario.input), commits.merge, repository);
  if (scenario.valid) assert.ok(execute().length); else assert.throws(execute);
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
  assert.ok(!htmlGraph(rows, 'canary', commits.merge).includes('<script'));
  assert.equal(history({ from: 'beginning', source_sha: commits.merge }, repository).commits.length, cases.history.beginning_count);
  assert.equal(history({ from: commits.root, source_sha: commits.root }, repository).contributors.length, 0);
});
test('release metadata names match linked assets and final checksums', () => {
  const dir = path.join(root, 'asset-names');
  const metadata = { channel: 'canary', source_sha: commits.merge, selection_hash: sha256('range'), targets: [] };
  write(`${dir}/notes.md`, `![Graph](https://github.com/example/project/releases/download/canary/canary-${commits.merge}-graph-001.png)`);
  write(`${dir}/graph-001.png`, 'graph');
  const result = finalizeAssets(dir, metadata, ['notes.md', 'graph-001.png']);
  const notes = fs.readFileSync(`${dir}/notes.md`, 'utf8');
  for (const asset of result.assets) assert.equal(asset.sha256, sha256(fs.readFileSync(`${dir}/${asset.path}`)));
  assert.ok(notes.includes('/' + result.assets.find(asset => asset.path === 'graph-001.png').name + ')'));
  assert.equal(JSON.parse(fs.readFileSync(`${dir}/release.json`)).generation, result.generation);
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
test('source rules require no direct-push bypass and only admin PR merging', () => {
  const sets = ['source-checks', 'source-admins'].map(name => JSON.parse(fs.readFileSync(`ci/releases/protection/${name}.json`)));
  assert.equal(protectionsValid(sets), true);
  assert.equal(protectionsValid([sets[0]]), false);
  const unsafe = structuredClone(sets); unsafe[0].bypass_actors = [{ actor_id: 5, actor_type: 'RepositoryRole', bypass_mode: 'always' }];
  assert.equal(protectionsValid(unsafe), false);
});
for (const [index, scenario] of cases.publication.entries()) test(scenario.name, async () => {
  const dir = path.join(root, 'publisher', String(index));
  write(`${dir}/notes.md`, 'Selected new source'); write(`${dir}/packages.tar.gz`, 'new packages');
  const metadata = { channel: 'canary', source_sha: commits.merge, selection_hash: sha256('selection'), prerelease: true, targets: [],
    assets: [{ path: 'packages.tar.gz', name: `canary-${commits.merge}-packages.tar.gz`, sha256: sha256('new packages') }] };
  write(`${dir}/release.json`, metadata);
  const existing = scenario.initial !== false;
  let ref = existing ? { object: { sha: commits.root } } : null;
  let release = existing ? { id: 1, body: 'old notes', name: 'canary', draft: false, prerelease: true, upload_url: 'https://uploads.github.com/release/1{?name}' } : null;
  let assets = existing ? [{ id: 2, name: 'manual-attachment.txt' }] : [], next = 3, fresh = 0, uploaded = 0;
  const api = {
    async pages() { return structuredClone(assets); },
    async request(route, options = {}) {
      if (route.startsWith('https://uploads')) {
        if (scenario.failure === 'upload') throw Error('upload failed');
        uploaded++;
        const asset = { id: next++, name: new URL(route).searchParams.get('name'), size: options.body.length, digest: `sha256:${sha256(options.body)}` };
        assets.push(asset); return structuredClone(asset);
      }
      if (options.method === 'DELETE') {
        if (route === '/releases/1') { release = null; assets = []; }
        else if (route.startsWith('/git/refs/')) ref = null;
        else assets = assets.filter(asset => asset.id !== Number(route.split('/').at(-1)));
        return null;
      }
      if (route.startsWith('/git/ref/')) return structuredClone(ref);
      return structuredClone(release);
    },
    async json(method, route, data) {
      if (route === '/releases' && method === 'POST') {
        release = { id: 1, ...data, upload_url: 'https://uploads.github.com/release/1{?name}' };
        if (scenario.draft_tag) ref = { object: { sha: data.target_commitish } };
        return structuredClone(release);
      }
      if (route.startsWith('/git/refs')) { ref = { object: { sha: data.sha } }; return structuredClone(ref); }
      if (scenario.failure === 'body' && data.body !== 'old notes') throw Error('body update failed');
      release = { ...release, ...data }; return structuredClone(release);
    },
  };
  const assertFresh = async () => { if (++fresh === 2 && scenario.failure === 'stale') throw Error('source advanced'); };
  const operation = () => updateChannel(api, metadata, dir, assertFresh);
  if (scenario.valid) {
    await operation(); assert.equal(ref.object.sha, commits.merge); assert.ok(release.body.includes('release-generation:'));
    if (scenario.repeat) { const before = uploaded; await operation(); assert.equal(uploaded, before); }
  } else {
    await assert.rejects(operation);
    if (existing) {
      assert.equal(ref.object.sha, commits.root); assert.equal(release.body, 'old notes');
      assert.deepEqual(assets, [{ id: 2, name: 'manual-attachment.txt' }]);
    } else { assert.equal(ref, null); assert.equal(release, null); assert.deepEqual(assets, []); }
  }
});
test('local publication is denied before network access', async () => {
  const previous = process.env.ACT;
  process.env.ACT = 'true';
  try { await assert.rejects(() => publish('canary'), /Local or untrusted/); }
  finally { if (previous === undefined) delete process.env.ACT; else process.env.ACT = previous; }
});
test('temporary GET failures retry', async () => {
  let requests = 0;
  const api = client('test', 'example/project', async () => ++requests === 1
    ? new Response('unavailable', { status: 503 }) : new Response('{"ok":true}', { status: 200 }));
  assert.deepEqual(await api.request('/test'), { ok: true }); assert.equal(requests, 2);
});
