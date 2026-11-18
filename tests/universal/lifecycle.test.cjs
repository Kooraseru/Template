'use strict';
const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const root = path.resolve(__dirname, "../..");

test('PR admission and retirement have isolated permissions', () => {
  const read = filename => fs.readFileSync(path.join(root, '.github/workflows', filename), 'utf8');
  const review=read('pull.yml'), close=read('close.yml');
  assert.match(review,/pull_request_target:/);
  assert.match(review,/CI_OPERATION: review/);
  assert.doesNotMatch(review,/checkout@|pull-requests: write|secrets:/);
  assert.match(close,/pull-requests: write/);
  assert.match(close,/types: \[closed\]/);
  assert.match(close,/head.repo.full_name == github.repository/);
  assert.match(close,/publish\.cjs --retire/);
  assert.doesNotMatch(close,/bootstrap\.yml|CI-Engine/);
  const config=JSON.parse(fs.readFileSync(path.join(root,'config/ci/operations.json'),'utf8'));
  assert.equal(config.operations['preview-retire'],undefined);
});
test('dropdown choices correspond to configured manual operations', () => {
  const workflow = fs.readFileSync(path.join(root, '.github/workflows/manual.yml'), 'utf8');
  const config = JSON.parse(fs.readFileSync(path.join(root,
    'config/ci/operations.json'), 'utf8'));
  const options = workflow.split('      operation:')[1].split('      publish:')[0];
  const configured = Object.entries(config.operations).filter(([, op]) => op.events.includes("workflow_dispatch")).map(([name]) => name).sort();
  const choices = [...options.matchAll(/^          - ([a-z][a-z0-9-]*)$/gm)].map(m => m[1]).sort();
  assert.deepEqual(choices, configured);
  assert.match(workflow, /      preview_kind:/);
  assert.match(workflow, /      preview_pr:/);
  assert.match(workflow, /      preview_branch:/);
});
