'use strict';
const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const os = require('node:os');

const { section, settings, target, sourceContext, resolveTarget } = require('./config.cjs');
const { render } = require('./launch.cjs');
const { assets, update, exportSite } = require('./state.cjs');
const { aliasFromEnv } = require('./publish.cjs');

function temporary(t) {
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'ci-preview-'));
  t.after(() => fs.rmSync(dir, { recursive: true, force: true }));
  return dir;
}
function config() {
  return { enabled: true, provider: 'github-pages', path_prefix: 'previews',
    state_branch: 'pages-state', retention_days: 14,
    pull_requests: true, branches: true, repo: 'Kooraseru/Template',
    owner: 'Kooraseru', name: 'Template', base: '/Template/',
    site: 'https://kooraseru.github.io', cloudflare_project: 'template',
    accountId: '0'.repeat(32) };
}

test('provider configuration validates both destinations', t => {
  const file = path.join(temporary(t), 'config.toml');
  fs.writeFileSync(file, '[github.previews]\nenabled = true\nprovider = "github-pages"\n');
  assert.equal(section(file, 'github.previews').provider, 'github-pages');
  assert.equal(settings(file, { GITHUB_REPOSITORY: 'Kooraseru/Template' }).base, '/Template/');
  fs.writeFileSync(file, '[github.previews]\nenabled = true\nprovider = "cloudflare-pages"\ncloudflare_project = "template"\n');
  assert.equal(settings(file, { GITHUB_REPOSITORY: 'Kooraseru/Template' }).provider, 'cloudflare-pages');
  fs.writeFileSync(file, '[github.previews]\nenabled = true\nprovider = "cloudflare-pages"\n');
  assert.throws(() => settings(file, { GITHUB_REPOSITORY: 'Kooraseru/Template' }), /cloudflare_project/);
});

test('targets reject reserved or malformed identities', () => {
  const c = config();
  assert.equal(target('pr:50', c).alias, 'pr-50');
  assert.equal(target('delete:pr:50', c).remove, true);
  assert.match(target('branch:demo/header-redesign', c).alias,
    /^branch-demo-header-redesign-[0-9a-f]{8}$/);
  for (const value of ['pr:0', 'pr:abc', 'branch:source',
    'branch:ci/generated', 'branch:../root', 'branch:foo?bar', 'other'])
    assert.throws(() => target(value, c), /Invalid|reserved|must begin/);
});

test('dispatch accepts only trusted explicit source invocations', t => {
  const event = path.join(temporary(t), 'event.json');
  fs.writeFileSync(event, JSON.stringify({ inputs: { preview_target: 'pr:50' } }));
  const ctx = { GITHUB_ACTIONS: 'true', GITHUB_EVENT_NAME: 'workflow_dispatch',
    GITHUB_REF: 'refs/heads/source', CI_DEFAULT_BRANCH: 'source',
    CI_ENGINE_OPERATION: 'preview', CI_PUBLICATION_ENABLED: 'true',
    GITHUB_SHA: 'a'.repeat(40), GITHUB_RUN_ID: '123',
    GITHUB_RUN_ATTEMPT: '1', GITHUB_EVENT_PATH: event };
  assert.equal(sourceContext(ctx).target, 'pr:50');
  assert.throws(() => sourceContext({ ...ctx, GITHUB_REF: 'refs/heads/topic' }),
    /trusted source/);
  assert.throws(() => sourceContext({ ...ctx, CI_PUBLICATION_ENABLED: 'false' }),
    /trusted source/);
});

test('only open internal PRs can be previewed', async () => {
  const c = config(), selected = target('pr:50', c), sha = 'b'.repeat(40);
  const pr = { state: 'open', base: { repo: { full_name: c.repo } },
    head: { repo: { full_name: c.repo }, sha } };
  assert.equal((await resolveTarget(selected, c, async () => pr)).sha, sha);
  await assert.rejects(resolveTarget(selected, c, async () =>
    ({ ...pr, head: { repo: { full_name: 'other/repo' }, sha } })),
  /originate from this repository/);
});

test('generated preview separates untrusted compilation and source-only publishing', () => {
  const c = config(), candidate = { ...target('pr:50', c), sha: 'b'.repeat(40) };
  const ctx = { sha: 'a'.repeat(40), target: 'pr:50',
    branch: 'ci/preview-123-1-aaaaaaaaaa' };
  const graph = JSON.parse(render(ctx, candidate, c)['pipeline.yml'].split('\n').slice(1).join('\n'));
  assert.equal(graph.jobs.build.permissions.contents, 'read');
  assert.equal(graph.jobs.build.steps[0].with.ref, candidate.sha);
  assert.equal(graph.jobs.build.steps[2].env.DOCS_BASE, '/Template/previews/pr-50/');
  assert.ok(!JSON.stringify(graph.jobs.build).includes('secrets.'));
  assert.equal(graph.jobs.publish.steps[0].with.ref, ctx.sha);
  assert.equal(graph.jobs.publish.permissions.pages, 'write');
  assert.equal(graph.jobs.publish.permissions.contents, 'write');
  assert.equal(graph.jobs.publish.concurrency.group, 'pages-site-' + '$' + '{{ github.repository }}');
  assert.ok(graph.jobs.publish.steps.some(x => x.uses === 'actions/deploy-pages@v4'));

  const other = JSON.parse(render(ctx, candidate, { ...c,
    provider: 'cloudflare-pages' })['pipeline.yml'].split('\n').slice(1).join('\n'));
  assert.equal(other.jobs.publish.permissions.contents, 'read');
  assert.equal(other.jobs.publish.environment.name, 'ci-preview-cloudflare');
  assert.ok(!other.jobs.publish.steps.some(x => x.uses === 'actions/deploy-pages@v4'));
  assert.equal(other.jobs.build.steps[2].env.DOCS_BASE, '/Template/');
});

test('publishing rejects a forged target alias', () => {
  const c = config(), sha = 'b'.repeat(40);
  assert.equal(aliasFromEnv(c, { CI_PREVIEW_TARGET: 'pr:50',
    CI_PREVIEW_ALIAS: 'pr-50', CI_PREVIEW_SHA: sha }).alias, 'pr-50');
  assert.throws(() => aliasFromEnv(c, { CI_PREVIEW_TARGET: 'pr:50',
    CI_PREVIEW_ALIAS: 'pr-51', CI_PREVIEW_SHA: sha }), /alias mismatch/);
});

function mockGitHub() {
  let tick = 0;
  const blob = new Map(), tree = new Map(), commit = new Map(), refs = new Map();
  const next = () => (++tick).toString(16).padStart(40, '0');
  const api = async (method, resource, body) => {
    let m;
    if (method === 'GET' && (m = resource.match(/^\/git\/ref\/heads\/(.+)$/))) {
      if (!refs.has(m[1])) { const e = new Error('Not found'); e.status = 404; throw e; }
      return { object: { sha: refs.get(m[1]) } };
    }
    if (method === 'GET' && (m = resource.match(/^\/git\/commits\/([0-9a-f]{40})$/)))
      return commit.get(m[1]);
    if (method === 'GET' && (m = resource.match(/^\/git\/trees\/([0-9a-f]{40})\?recursive=1$/)))
      return { truncated: false, tree: [...tree.get(m[1]).values()] };
    if (method === 'GET' && (m = resource.match(/^\/git\/blobs\/([0-9a-f]{40})$/)))
      return { encoding: 'base64', content: blob.get(m[1]) };
    if (method === 'POST' && resource === '/git/blobs') {
      const id = next(); blob.set(id, body.content); return { sha: id };
    }
    if (method === 'POST' && resource === '/git/trees') {
      const values = body.base_tree ? new Map(tree.get(body.base_tree)) : new Map();
      for (const value of body.tree)
        if (value.sha === null) values.delete(value.path);
        else values.set(value.path, value);
      const id = next(); tree.set(id, values); return { sha: id };
    }
    if (method === 'POST' && resource === '/git/commits') {
      const id = next(); commit.set(id, { tree: { sha: body.tree } }); return { sha: id };
    }
    if (method === 'POST' && resource === '/git/refs') {
      refs.set(body.ref.replace('refs/heads/', ''), body.sha); return {};
    }
    if (method === 'PATCH' && (m = resource.match(/^\/git\/refs\/heads\/(.+)$/))) {
      refs.set(m[1], body.sha); return {};
    }
    throw new Error('Unexpected mock GitHub operation: ' + method + ' ' + resource);
  };
  return api;
}

test('production and previews remain independent across updates and cleanup', async t => {
  const dir = temporary(t), source = path.join(dir, 'production'),
    branch = path.join(dir, 'preview'), output = path.join(dir, 'output');
  fs.mkdirSync(source); fs.mkdirSync(branch);
  fs.writeFileSync(path.join(source, 'index.html'), 'version 1');
  fs.writeFileSync(path.join(branch, 'index.html'), 'PR 50');
  const c = config(), api = mockGitHub();
  await update(c, { kind: 'production', directory: source }, api);
  const candidate = { ...target('pr:50', c), sha: 'b'.repeat(40) };
  await update(c, { kind: 'preview', target: candidate, directory: branch }, api);
  await exportSite(c, api, output);
  assert.equal(fs.readFileSync(path.join(output, 'index.html'), 'utf8'), 'version 1');
  assert.equal(fs.readFileSync(path.join(output, 'previews/pr-50/index.html'), 'utf8'), 'PR 50');
  fs.writeFileSync(path.join(source, 'index.html'), 'version 2');
  await update(c, { kind: 'production', directory: source }, api);
  await exportSite(c, api, output);
  assert.equal(fs.readFileSync(path.join(output, 'index.html'), 'utf8'), 'version 2');
  assert.ok(fs.existsSync(path.join(output, 'previews/pr-50/index.html')));
  await update(c, { kind: 'remove', target: { ...candidate, remove: true } }, api);
  await exportSite(c, api, output);
  assert.ok(!fs.existsSync(path.join(output, 'previews/pr-50/index.html')));
});

test('production assets cannot shadow reserved previews', t => {
  const folder = path.join(temporary(t), 'site');
  fs.mkdirSync(path.join(folder, 'previews'), { recursive: true });
  fs.writeFileSync(path.join(folder, 'index.html'), 'production');
  fs.writeFileSync(path.join(folder, 'previews/index.html'), 'reserved');
  assert.throws(() => assets(folder, 'site/'), /cannot overwrite preview paths/);
});
