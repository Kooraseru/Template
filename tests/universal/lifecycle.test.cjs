'use strict';
const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const root = path.resolve(__dirname, "../..");

test('PR review and protected close have one engine each and isolated permissions', () => {
  const read = filename => fs.readFileSync(path.join(root, '.github/workflows', filename), 'utf8');
  const review = read('pull.yml'), close = read('close.yml');
  assert.match(review, /operation: review/);
  assert.doesNotMatch(review, /pull_request_target|pull-requests: write|secrets:/);
  assert.match(close, /operation: preview-retire/);
  assert.match(close, /pull-requests: write/);
  assert.match(close, /types: \[closed\]/);
  assert.match(close, /head.repo.full_name == github.repository/);
  for (const source of [review, close]) {
    assert.equal([...source.matchAll(/uses: \.\/\.github\/workflows\/bootstrap\.yml/g)].length, 1);
    assert.doesNotMatch(source, /CI Engine Retirement/);
  }
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
