'use strict';
const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');
const { settings, target, workflowTarget, sourceContext, resolveTarget } = require('./config.cjs');
const { render } = require('./launch.cjs');
const { selected, prepareUpload, retireClosed, pruneRetired } = require('./publish.cjs');
const { marker, bodyFor, syncComment } = require('./comment.cjs');

function temporary(t) {
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'ci-preview-'));
  t.after(() => fs.rmSync(dir, { recursive: true, force: true }));
  return dir;
}
const repo = 'Kooraseru/Template';
function config() {
  return { enabled: true, cloudflare_project: 'template', retention_days: 14,
    pull_requests: true, branches: true, repo, owner: 'Kooraseru',
    name: 'Template', base: '/Template/', accountId: '0'.repeat(32) };
}
test('Cloudflare is the only preview backend and requires a project', t => {
  const file = path.join(temporary(t), 'config.toml');
  fs.writeFileSync(file, '[github.previews]\nenabled = true\ncloudflare_project = "template"\n');
  assert.equal(settings(file, { GITHUB_REPOSITORY: repo }).cloudflare_project, 'template');
  fs.writeFileSync(file, '[github.previews]\nenabled = true\ncloudflare_project = ""\n');
  assert.throws(() => settings(file, { GITHUB_REPOSITORY: repo }), /cloudflare_project/);
  const root = path.resolve(__dirname, '../../../../../..');
  const targets = fs.readFileSync(path.join(root, 'config/targets.toml'), 'utf8');
  assert.ok(!targets.includes('pages-state'));
  assert.ok(targets.includes('branches = false'));
});
test('preview targets are stable and reserved branches are rejected', () => {
  const c = config();
  assert.equal(target('pr:50', c).alias, 'pr-50');
  assert.equal(target('delete:pr:50', c).remove, true);
  assert.match(target('branch:demo/header', c).alias, /^branch-demo-header-[a-f0-9]{8}$/);
  for (const x of ['pr:0','pr:abc','branch:source','branch:ci/test',
    'branch:../bad','nonsense'])
    assert.throws(() => target(x, c), /Invalid|reserved|must begin/);
});
test('dispatch requires a trusted source revision and an explicit approval', t => {
  const event = path.join(temporary(t), 'event.json');
  fs.writeFileSync(event, JSON.stringify({ inputs: { preview_kind: 'pr', preview_pr: 50 } }));
  const ctx = { GITHUB_ACTIONS: 'true', GITHUB_EVENT_NAME: 'workflow_dispatch',
    GITHUB_REF: 'refs/heads/source', CI_DEFAULT_BRANCH: 'source',
    CI_ENGINE_OPERATION: 'preview', CI_PUBLICATION_ENABLED: 'true',
    GITHUB_SHA: 'a'.repeat(40), GITHUB_RUN_ID: '123',
    GITHUB_RUN_ATTEMPT: '1', GITHUB_EVENT_PATH: event };
  assert.equal(sourceContext(ctx).target, 'pr:50');
  assert.throws(() => sourceContext({ ...ctx, GITHUB_REF: 'refs/heads/topic' }), /trusted source/);
});
test('typed workflow choices build valid preview targets without manual prefixes', () => {
  assert.equal(workflowTarget({ preview_kind: 'pr', preview_pr: 52 }), 'pr:52');
  assert.equal(workflowTarget({ preview_kind: 'delete-pr', preview_pr: '52' }), 'delete:pr:52');
  assert.equal(workflowTarget({ preview_kind: 'branch', preview_branch: 'feature/docs' }),
    'branch:feature/docs');
  assert.equal(workflowTarget({ preview_kind: 'delete-branch',
    preview_branch: 'feature/docs' }), 'delete:branch:feature/docs');
  assert.throws(() => workflowTarget({ preview_kind: 'pr',
    preview_pr: 'preview_pr=52' }), /valid preview_pr/);
  assert.throws(() => workflowTarget({ preview_kind: 'pr', preview_pr: 0 }),
    /valid preview_pr/);
  assert.throws(() => workflowTarget({ preview_kind: 'branch' }),
    /preview_branch/);
  assert.throws(() => workflowTarget({ preview_kind: 'unexpected' }),
    /preview_kind/);
});
test('only open same-repository PRs can be previewed', async () => {
  const sha = 'b'.repeat(40);
  const good = { state: 'open', base: { repo: { full_name: repo } },
    head: { repo: { full_name: repo }, sha } };
  assert.equal((await resolveTarget(target('pr:50', config()), config(),
    async () => good)).sha, sha);
  await assert.rejects(resolveTarget(target('pr:50', config()), config(),
    async () => ({ ...good, head: { repo: { full_name: 'someone/fork' }, sha } })),
    /originate from this repository/);
});
test('Cloudflare publishing is isolated from untrusted static compilation', () => {
  const ctx = { sha: 'a'.repeat(40), target: 'pr:50',
    branch: 'ci/run-preview-123-1-aaaaaaaaaa' };
  const candidate = { ...target('pr:50', config()), sha: 'b'.repeat(40) };
  const graph = JSON.parse(render(ctx, candidate, config())['pipeline.yml']
    .split('\n').slice(1).join('\n'));
  assert.equal(graph.jobs.build.permissions.contents, 'read');
  assert.equal(graph.jobs.build.steps[0].with.ref, candidate.sha);
  assert.equal(graph.jobs.build.steps[2].env.DOCS_BASE, '/Template/');
  assert.equal(graph.jobs.publish.steps[0].with.ref, ctx.sha);
  assert.equal(graph.jobs.publish.permissions.contents, 'read');
  assert.equal(graph.jobs.publish.permissions.actions, 'read');
  assert.equal(graph.jobs.publish.permissions['pull-requests'], 'write');
  assert.equal(graph.jobs.publish.environment.name, 'ci-preview-cloudflare');
  assert.ok(!JSON.stringify(graph.jobs.build).includes('secrets.'));
  assert.ok(!JSON.stringify(graph).includes('deploy-pages@'));
  assert.ok(graph.jobs.publish.steps.some(x =>
    x.run === 'node .github/components/documentation/pages/publish/preview/publish.cjs --preview'));
  const closed = JSON.parse(render(ctx, { ...candidate, remove: true }, config())['pipeline.yml']
    .split('\n').slice(1).join('\n'));
  assert.equal(closed.jobs.build, undefined);
  assert.ok(!closed.jobs.publish.steps.some(x => x.uses === 'actions/download-artifact@v8'));
});
test('a forged preview target alias is rejected', () => {
  assert.equal(selected({ CI_PREVIEW_TARGET: 'pr:50', CI_PREVIEW_ALIAS: 'pr-50',
    CI_PREVIEW_SHA: 'b'.repeat(40) }, config()).alias, 'pr-50');
  assert.throws(() => selected({ CI_PREVIEW_TARGET: 'pr:50', CI_PREVIEW_ALIAS: 'pr-51',
    CI_PREVIEW_SHA: 'b'.repeat(40) }, config()), /alias mismatch/);
});
test('close events must match the repository and PR number', async t => {
  const eventFile = path.join(temporary(t), 'event.json');
  fs.writeFileSync(eventFile, JSON.stringify({ action: 'closed', repository: { full_name: repo },
    pull_request: { number: 50, base: { repo: { full_name: repo } },
      head: { repo: { full_name: repo } } } }));
  await assert.rejects(retireClosed({
    GITHUB_ACTIONS: 'true', GITHUB_EVENT_NAME: 'pull_request_target',
    GITHUB_EVENT_PATH: eventFile, GITHUB_REPOSITORY: repo,
    CI_PREVIEW_CLOSED_NUMBER: '51'
  }), /Invalid preview close event/);
});
test('retirement replaces preview with HTTP 410 Worker', t => {
  const output = prepareUpload(config(), { alias: 'pr-50', remove: true });
  t.after(() => fs.rmSync(output, { recursive: true, force: true }));
  const content = fs.readFileSync(path.join(output, '_worker.js'), 'utf8');
  assert.ok(content.includes('status: 410'));
  assert.ok(content.includes('no-store'));
  assert.ok(fs.existsSync(path.join(output, 'index.html')));
});

test('Cloudflare cleanup deletes only prior deployments of the selected PR', async () => {
  const calls = [];
  const keep = '00000000-0000-0000-0000-000000000050';
  const older = '00000000-0000-0000-0000-000000000049';
  const other = '00000000-0000-0000-0000-000000000060';
  const deployments = [
    { id: older, environment: 'preview', created_on: '2026-11-15T00:00:00Z',
      deployment_trigger: { metadata: { branch: 'pr-50' } } },
    { id: keep, environment: 'preview', created_on: '2026-11-16T00:00:00Z',
      deployment_trigger: { metadata: { branch: 'pr-50' } } },
    { id: other, environment: 'preview', created_on: '2026-11-16T00:00:00Z',
      deployment_trigger: { metadata: { branch: 'pr-60' } } },
  ];
  const mock = async (url, init) => {
    calls.push({ url, method: init.method });
    if (init.method === 'GET') return {
      ok: true, json: async () => ({ success: true, result: deployments,
        result_info: { total_pages: 1 } })
    };
    assert.ok(url.includes(older));
    return { ok: true, json: async () => ({ success: true }) };
  };
  const removed = await pruneRetired(config(), target('delete:pr:50', config()),
    { CLOUDFLARE_API_TOKEN: 'example' }, mock);
  assert.equal(removed, 1);
  assert.equal(calls.filter(x => x.method === 'DELETE').length, 1);
  assert.ok(!calls.some(x => x.url.includes(other)));
  assert.ok(!calls.some(x => x.url.includes(keep)));
});


test('a successful PR preview produces a live link, but closed notes contain none', () => {
  const c = config(), candidate = {
    ...target('pr:52', c), sha: 'a'.repeat(40)
  };
  const live = bodyFor(c, candidate, false);
  assert.ok(live.includes(marker));
  assert.ok(live.includes('https://pr-52.template.pages.dev/Template/'));
  assert.ok(live.includes('/commit/' + candidate.sha));
  const closed = bodyFor(c, { ...candidate, remove: true }, true);
  assert.ok(closed.includes('Closed'));
  assert.ok(!closed.includes('pages.dev'));
  assert.throws(() => bodyFor(c, { ...candidate, sha: undefined }, false),
    /published revision/);
});

test('PR comments are created once and updated in place across deployments', async () => {
  const configValue = config(), env = { GH_TOKEN: 'test-token' };
  const existing = [];
  const calls = [];
  const request = async (method, resource, token, body) => {
    calls.push({ method, resource, body });
    assert.equal(token, env.GH_TOKEN);
    if (method === 'GET') return [...existing];
    if (method === 'POST') {
      assert.equal(resource, '/repos/Kooraseru/Template/issues/52/comments');
      const result = { id: 100, user: { id: 41898282, login: 'github-actions[bot]' },
        body: body.body };
      existing.push(result);
      return result;
    }
    if (method === 'PATCH') {
      assert.equal(resource, '/repos/Kooraseru/Template/issues/comments/100');
      existing[0].body = body.body;
      return existing[0];
    }
    throw new Error('Unexpected API request');
  };
  const candidate = { ...target('pr:52', configValue), sha: 'a'.repeat(40) };
  assert.equal((await syncComment(configValue, candidate, env, false, request)).action, 'created');
  assert.equal((await syncComment(configValue, candidate, env, false, request)).action, 'unchanged');
  const next = { ...candidate, sha: 'b'.repeat(40) };
  assert.equal((await syncComment(configValue, next, env, false, request)).action, 'updated');
  assert.equal((await syncComment(configValue, next, env, true, request)).action, 'updated');
  assert.ok(existing[0].body.includes('Closed'));
  assert.equal(calls.filter(x => x.method === 'POST').length, 1);
  assert.equal(calls.filter(x => x.method === 'PATCH').length, 2);
});

test('PR comments cannot edit other authors or post closure-only notes', async () => {
  const c = config(), env = { GH_TOKEN: 'test-token' };
  const candidate = { ...target('pr:52', c), sha: 'a'.repeat(40) };
  const spoof = { id: 44, user: { login: 'someone-else', id: 1 },
    body: marker + '\nspoofed' };
  const calls = [];
  const request = async (method, resource, token, body) => {
    calls.push({ method, resource });
    if (method === 'GET') return [spoof];
    if (method === 'POST') return { id: 99 };
    throw new Error('Unexpected API action');
  };
  assert.equal(await syncComment(c, candidate, env, true, request), null);
  assert.equal(calls.length, 1);
  assert.equal((await syncComment(c, candidate, env, false, request)).action, 'created');
  assert.equal(calls.at(-1).method, 'POST');
  assert.equal(await syncComment(c, { ...target('branch:demo/test', c),
    sha: 'a'.repeat(40) }, env, false, request), null);
});
