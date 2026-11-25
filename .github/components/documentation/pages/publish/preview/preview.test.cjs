'use strict';
const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');
const { settings, target, workflowTarget, resolveTarget } = require('./config.cjs');
const { publishNative, resolveManual, publishManual, copyStatic, prepareUpload, retireClosed, pruneRetired, verifyProjectHost } = require('./publish.cjs');
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
    name: 'Template', base: '/Kooraseru/Template/', accountId: '0'.repeat(32) };
}
test('Cloudflare is the only preview backend and requires a project', t => {
  const file = path.join(temporary(t), 'config.toml');
  fs.writeFileSync(file, '[github.previews]\nenabled = true\ncloudflare_project = "template"\n');
  const configured = settings(file, { GITHUB_REPOSITORY: repo });
  assert.equal(configured.cloudflare_project, 'template');
  assert.equal(configured.base, '/Kooraseru/Template/');
  assert.equal(settings(file, { GITHUB_REPOSITORY: 'Example/example.github.io' }).base,
    '/Example/example.github.io/');
  fs.writeFileSync(file, '[github.previews]\nenabled = true\ncloudflare_project = ""\n');
  assert.throws(() => settings(file, { GITHUB_REPOSITORY: repo }), /cloudflare_project/);
  const root = path.resolve(__dirname, '../../../../../..');
  const targets = fs.readFileSync(path.join(root, 'config/targets.toml'), 'utf8');
  assert.ok(!targets.includes('pages-state'));
  assert.ok(!targets.includes('[github.publication]'));
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
test('retirement requires a trusted resolved closure and verifies current PR state', async () => {
  const sha = 'b'.repeat(40);
  const env = { GITHUB_ACTIONS: 'true', GITHUB_EVENT_NAME: 'workflow_run',
    PR_NUMBER: '50', REQUEST_SHA: sha, CI_DEFAULT_BRANCH: 'source', GITHUB_REPOSITORY: repo, GH_TOKEN: 'test-token' };
  const pr = { number: 50, state: 'closed', base: { ref: 'source', repo: { full_name: repo } },
    head: { sha, repo: { full_name: repo } } };
  await assert.rejects(retireClosed({...env, PR_NUMBER:'0'}, async () => { throw Error('Unexpected API'); }), /trusted resolved/);
  for (const invalid of [{...pr,state:'open'}, {...pr,head:{...pr.head,sha:'c'.repeat(40)}},
    {...pr,base:{...pr.base,ref:'other'}}]) {
    assert.equal(await retireClosed(env, async (method,resource) => {
      assert.equal(method,'GET'); assert.match(resource,/\/pulls\/50$/); return invalid;
    }),null);
  }
  const retired={id:42,user:{id:41898282},body:bodyFor(config(),target('delete:pr:50',config()),true)};
  for(const comments of [[],[retired]]){
    let calls=0;
    assert.equal(await retireClosed(env,async(method,resource)=>{
      assert.equal(method,'GET'); calls++;
      if(resource.endsWith('/pulls/50')) return pr;
      assert.match(resource,/\/issues\/50\/comments/); return comments;
    }),null);
    assert.equal(calls,2);
  }
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
  assert.equal(new URL(calls[0].url).searchParams.get('per_page'), '25');
  assert.equal(calls.filter(x => x.method === 'DELETE').length, 1);
  assert.ok(!calls.some(x => x.url.includes(other)));
  assert.ok(!calls.some(x => x.url.includes(keep)));
});



test('Cloudflare cleanup exposes bounded API errors for listing and deletion', async () => {
  const candidate = target('delete:pr:50', config());
  const env = { CLOUDFLARE_API_TOKEN: 'example' };
  await assert.rejects(pruneRetired(config(), candidate, env, async () => ({
    ok: false, status: 400, json: async () => ({
      success: false, errors: [{ code: 80001, message: 'Invalid list parameter' }]
    })
  })), /Cloudflare cleanup GET HTTP 400 \(80001: Invalid list parameter\)/);

  const newest = { id: '00000000-0000-0000-0000-000000000050',
    environment: 'preview', created_on: '2026-11-16T00:00:00Z',
    deployment_trigger: { metadata: { branch: 'pr-50' } } };
  const older = { ...newest, id: '00000000-0000-0000-0000-000000000049',
    created_on: '2026-11-15T00:00:00Z' };
  await assert.rejects(pruneRetired(config(), candidate, env, async (url, init) =>
    init.method === 'GET'
      ? { ok: true, status: 200, json: async () => ({
          success: true, result: [newest, older], result_info: { total_pages: 1 }
        }) }
      : { ok: false, status: 400, json: async () => ({
          success: false, errors: [{ code: 80002, message: 'Deployment cannot be deleted' }]
        }) }
  ), /Cloudflare cleanup DELETE HTTP 400 \(80002: Deployment cannot be deleted\)/);
});

test('a successful PR preview produces a live link, but closed notes contain none', () => {
  const c = config(), candidate = {
    ...target('pr:52', c), sha: 'a'.repeat(40)
  };
  const live = bodyFor(c, candidate, false);
  assert.ok(live.includes(marker));
  assert.ok(live.includes('https://pr-52.template.pages.dev/Kooraseru/Template/'));
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

test('preview publishing treats candidate artifacts as static data only', t => {
  const tmp=temporary(t),src=path.join(tmp,'src'),dest=path.join(tmp,'dest');
  fs.mkdirSync(src);fs.writeFileSync(path.join(src,'index.html'),'html');
  copyStatic(src,dest);assert.equal(fs.readFileSync(path.join(dest,'index.html'),'utf8'),'html');
  for(const file of ['_worker.js','_routes.json','_headers','_redirects','wrangler.toml','functions']){
    fs.writeFileSync(path.join(src,file),'bad');
    assert.throws(()=>copyStatic(src,dest),/Forbidden/);
    fs.rmSync(path.join(src,file));
  }
  if(process.platform!=='win32'){
    fs.symlinkSync(path.join(src,'index.html'),path.join(src,'link'));
    assert.throws(()=>copyStatic(src,dest),/Linked/);
  }
});

test('Cloudflare project names and assigned public hostnames are distinct', async () => {
  const c={...config(),cloudflare_domain:'template-2pq.pages.dev'};
  const candidate={...target('pr:55',c),sha:'c'.repeat(40)};
  assert.match(bodyFor(c,candidate,false),/https:\/\/pr-55\.template-2pq\.pages\.dev\/Kooraseru\/Template\//);
  const mock=async()=>({ok:true,json:async()=>({success:true,result:{subdomain:'template-2pq.pages.dev'}})});
  assert.equal(await verifyProjectHost(c,{CLOUDFLARE_API_TOKEN:'test'},mock),'template-2pq.pages.dev');
  await assert.rejects(verifyProjectHost(config(),{CLOUDFLARE_API_TOKEN:'test'},mock),/Set github.previews.cloudflare_domain/);
});

test('native preview verifies current same-repository PR before deployment or comment', async () => {
  const sha = 'b'.repeat(40);
  const env = { GITHUB_ACTIONS:'true', GITHUB_EVENT_NAME:'workflow_run', PR_NUMBER:'50',
    REQUEST_SHA:sha, CI_DEFAULT_BRANCH:'source', GITHUB_REPOSITORY:repo };
  const pr = { number:50, state:'open', base:{ref:'source',repo:{full_name:repo}},head:{sha,repo:{full_name:repo}} };
  const calls = [];
  const deploy = async (c, v) => { calls.push('deploy'); assert.equal(v.sha,sha); return 'deployed'; };
  const comment = async () => { calls.push('comment'); };
  assert.equal(await publishNative(env,deploy,async()=>({...pr,state:'closed'}),comment),null);
  assert.deepEqual(calls,[]);
  assert.equal(await publishNative(env,deploy,async()=>pr,comment),'deployed');
  assert.deepEqual(calls,['deploy','comment']);
  await assert.rejects(publishNative({...env,GITHUB_EVENT_NAME:'pull_request'},deploy,async()=>pr,comment),/trusted completed/);
});
test('manual preview rejects stale or forged resolved targets and non-default dispatch', async () => {
  const sha = 'b'.repeat(40);
  const env = { GITHUB_ACTIONS:'true',GITHUB_EVENT_NAME:'workflow_dispatch',GITHUB_REF:'refs/heads/source',
    CI_DEFAULT_BRANCH:'source',GITHUB_REPOSITORY:repo,PREVIEW_INPUTS:JSON.stringify({preview_kind:'branch',preview_branch:'demo/site'}) };
  const request=async()=>({object:{sha}});
  const selected=await resolveManual(env,request);
  assert.equal(selected.sha,sha);
  assert.equal(selected.base,'/Kooraseru/Template/');
  let count=0;
  const deploy=async()=>{count++;return 'deployed'};
  const resolved={...env,PREVIEW_TARGET:selected.requested,PREVIEW_ALIAS:selected.alias,REQUEST_SHA:sha};
  await assert.rejects(publishManual({...resolved,PREVIEW_ALIAS:'wrong'},deploy,request),/target mismatch/);
  await assert.rejects(publishManual({...resolved,REQUEST_SHA:'a'.repeat(40)},deploy,request),/changed while building/);
  await assert.rejects(resolveManual({...env,GITHUB_REF:'refs/heads/other'},request),/trusted default/);
  assert.equal(await publishManual(resolved,deploy,request),'deployed');
  assert.equal(count,1);
});
