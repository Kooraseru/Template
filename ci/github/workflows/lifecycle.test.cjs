'use strict';
const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const { gitBlobHash, engineRevision, engineBlob, engineUrl, runLifecycle } =
  require('./lifecycle.cjs');

const root = path.resolve(__dirname, '../../..');

test('CI bootstrap YAML stays unchanged while event lifecycle is component-driven', () => {
  const workflow = fs.readFileSync(path.join(root, '.github/workflows/ci.yml'), 'utf8');
  assert.equal(gitBlobHash(workflow), '7cfa4706d08675a7aedea1dfc14c0a94ec7aa852');
  const config = JSON.parse(fs.readFileSync(
    path.join(root, '.github/config/ci/lifecycle.json'), 'utf8'));
  assert.equal(config.version, 1);
  const route = config.routes.find(r => r.event === 'pull_request_target' &&
    r.action === 'closed');
  assert.equal(route.component, 'lifecycle/preview-retire');
  assert.equal(route.sameRepository, true);
  const component = JSON.parse(fs.readFileSync(path.join(root,
    '.github/config/ci/components/lifecycle/preview-retire/component.json'), 'utf8'));
  assert.equal(component.boundary, 'privileged');
  assert.deepEqual(component.command, [
    'node', 'ci/components/documentation/pages/publish/preview/publish.cjs', '--retire'
  ]);
});

test('the closure entrypoint uses a pinned, content-addressed engine runner', () => {
  assert.match(engineRevision, /^[a-f0-9]{40}$/);
  assert.match(engineBlob, /^[a-f0-9]{40}$/);
  assert.equal(gitBlobHash('hello\n'), 'ce013625030ba8dba906f756967f9e9ca394464a');
  assert.equal(engineUrl, 'https://raw.githubusercontent.com/Kooraseru-Hub/CI-Engine/' +
    engineRevision + '/src/lifecycle/dispatch.cjs');
  const publisher = fs.readFileSync(path.join(root,
    'ci/components/documentation/pages/publish/preview/publish.cjs'), 'utf8');
  assert.match(publisher, /command === '--closed' \? \(\) =>/);
  assert.match(publisher, /command === '--retire' \? retireClosed/);
});

test('untrusted lifecycle entrypoints reject before any download', async () => {
  let requests = 0;
  await assert.rejects(runLifecycle({ GITHUB_ACTIONS: 'true',
    GITHUB_EVENT_NAME: 'pull_request' }, () => { requests++; }), /trusted PR target/);
  assert.equal(requests, 0);
});

test('a modified engine download never executes', async () => {
  let executed = false;
  const request = async () => ({ ok: true, text: async () => 'tampered' });
  await assert.rejects(runLifecycle({
    GITHUB_ACTIONS: 'true', GITHUB_EVENT_NAME: 'pull_request_target',
  }, request, () => { executed = true; }), /Git blob verification/);
  assert.equal(executed, false);
});
