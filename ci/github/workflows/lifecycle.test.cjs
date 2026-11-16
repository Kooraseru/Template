'use strict';
const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const root = path.resolve(__dirname, '../../..');

test('one authored CI job delegates close events to a pinned reusable engine', () => {
  const source = fs.readFileSync(path.join(root, '.github/workflows/ci.yml'), 'utf8');
  const jobs = source.split(/\njobs:\s*\n/)[1];
  assert.deepEqual([...jobs.matchAll(/^  ([\w-]+):$/gm)].map(m => m[1]), ['ci']);
  assert.match(source, /pull_request_target:/);
  assert.match(source, /types: \[closed\]/);
  assert.match(source, /uses: Kooraseru-Hub\/CI-Engine\/\.github\/workflows\/bootstrap\.yml@[a-f0-9]{40}/);
  assert.match(source, /pull-requests: write/);
  assert.doesNotMatch(source, /preview-close:|publish\.cjs --closed/);
});

test('project declares only its protected preview retirement component', () => {
  const config = JSON.parse(fs.readFileSync(path.join(root,
    '.github/config/ci/lifecycle.json'), 'utf8'));
  const route = config.routes.find(r => r.event === 'pull_request_target' && r.action === 'closed');
  assert.equal(route.component, 'lifecycle/preview-retire');
  assert.equal(route.sameRepository, true);
  const component = JSON.parse(fs.readFileSync(path.join(root,
    '.github/config/ci/components/lifecycle/preview-retire/component.json'), 'utf8'));
  assert.equal(component.boundary, 'privileged');
  assert.deepEqual(component.command,
    ['node', 'ci/components/documentation/pages/publish/preview/publish.cjs', '--retire']);
  assert.equal(fs.existsSync(path.join(root, 'ci/github/workflows/lifecycle.cjs')), false);
});

test('dropdown choices correspond to configured manual operations', () => {
  const workflow = fs.readFileSync(path.join(root, '.github/workflows/ci.yml'), 'utf8');
  const config = JSON.parse(fs.readFileSync(path.join(root,
    '.github/config/ci/engine.json'), 'utf8'));
  const options = workflow.split('      operation:')[1].split('      publish:')[0];
  for (const [name, operation] of Object.entries(config.operations)) {
    if (operation.events.includes('workflow_dispatch'))
      assert.match(options, new RegExp('^          - ' + name + '$', 'm'));
  }
  assert.match(workflow, /      preview_kind:/);
  assert.match(workflow, /      preview_pr:/);
  assert.match(workflow, /      preview_branch:/);
});
