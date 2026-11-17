'use strict';
const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const root = path.resolve(__dirname, '../../..');

test('PR review and privileged retirement share the pull workflow, not permissions', () => {
  const source = fs.readFileSync(path.join(root, '.github/workflows/pull.yml'), 'utf8');
  const jobs = source.split(/\njobs:\s*\n/)[1];
  assert.deepEqual([...jobs.matchAll(/^  ([\w-]+):$/gm)].map(m => m[1]), ['review', 'retire']);
  const [review, retire] = jobs.split(/\n  retire:/);
  assert.match(review, /operation: review/);
  assert.doesNotMatch(review, /pull-requests: write|secrets:/);
  assert.match(retire, /operation: preview-retire/);
  assert.match(retire, /pull-requests: write/);
  assert.match(source, /types: \[closed\]/);
});
test('project declares retirement as a normal protected component operation', () => {
  const config = JSON.parse(fs.readFileSync(path.join(root, 'config/ci/operations.json'), 'utf8'));
  const operation = config.operations['preview-retire'];
  assert.equal(operation.mode, 'protected');
  assert.deepEqual(operation.actions, ['closed']);
  assert.deepEqual(operation.events, ['pull_request_target']);
  assert.deepEqual(operation.components, ['lifecycle/preview-retire']);
  const component = JSON.parse(fs.readFileSync(path.join(root, '.github/components/lifecycle/preview-retire/component.json'), 'utf8'));
  assert.equal(component.boundary, 'privileged');
  assert.equal(fs.existsSync(path.join(root, 'config/ci/lifecycle.json')), false);
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
