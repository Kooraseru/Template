import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { spawnSync } from 'node:child_process';
import { definitions, normalize, parsePR, diagnostic, diagnosticReuseAllowed } from '../request.mjs';
import { renderChoices } from '../refresh-prs.mjs';
import { authorizePublication } from '../publication.mjs';
import { pendingReceiptAllowed } from '../pending-receipt.mjs';
import { sourceApproval } from '../source-approval.mjs';

test('the admin panel has twelve dropdowns and two explicit release inputs', () => {
  assert.equal(Object.keys(definitions).length, 14);
  assert.equal(Object.values(definitions).filter(definition => !definition.type).length, 12);
  for (const [key, definition] of Object.entries(definitions)) {
    for (const choice of definition.options || []) {
      assert.equal(normalize({ [key]: choice })[key], choice);
    }
  }
  assert.equal(normalize({ build_targets: 'windows-msvc-arm64' }).build_targets, 'windows-msvc-arm64');
  assert.throws(() => normalize({ compiler: 'arbitrary-command' }));
  assert.throws(() => normalize({ claim: '{}' }));
  assert.equal(normalize({}, false).operation, 'Full Run');
});

test('PR identity is parsed independently of its display title', () => {
  assert.equal(parsePR('#42 Fix builds'), 42);
  assert.equal(parsePR('Source'), 0);
  assert.throws(() => parsePR('#0 invalid'));
  assert.throws(() => parsePR('42'));
  assert.throws(() => normalize({ operation: 'Publish', pull_request: '#42 title' }));
  assert.throws(() => normalize({ operation: 'Full Run', pull_request: '#42 title' }));
  assert.throws(() => normalize({ operation: 'Publish', cache_policy: 'Rebuild outputs' }));
});

test('manual release inputs require an explicit valid version and full source commit', () => {
  const release_commit = 'a'.repeat(40);
  assert.equal(normalize({ release_version: '1.2.0', release_commit }).release_version, '1.2.0');
  assert.equal(normalize({ release_version: '1.3.0-pre.1', release_commit, release_output: 'Publish Pre-Release' }).release_version, '1.3.0-pre.1');
  assert.throws(() => normalize({ release_version: '1.2.0' }));
  assert.throws(() => normalize({ release_commit }));
  assert.throws(() => normalize({ release_version: '1.2.0', release_commit: 'latest' }));
  assert.throws(() => normalize({ release_version: '1.2.0', release_commit, release_output: 'Publish Pre-Release' }));
  assert.throws(() => normalize({ release_version: '1.2.0', release_commit, pull_request: '#17 title' }));
});

test('partial selections and gate overrides are diagnostic evidence', () => {
  assert.equal(diagnostic(normalize()), false);
  for (const override of [{ validation_scope: 'Receipts' }, { gate_policy: 'Ignore both' },
    { build_targets: 'Linux' }, { compiler: 'GCC' }, { architecture: 'ARM64' }]) {
    assert.equal(diagnostic(normalize(override)), true);
  }
});

test('PR dropdown refresh changes only its generated block and escapes titles', () => {
  const before = 'prefix\n        # BEGIN GENERATED PR CHOICES\n        options: ["Source"]\n        # END GENERATED PR CHOICES\nsuffix\n';
  const pulls = [{ number: 2, title: 'A "quote"\n options: [bad]' }, { number: 9, title: 'latest' }, { number: 3, title: 'closed', state: 'closed' }];
  const after = renderChoices(before, pulls);
  assert.ok(after.startsWith('prefix\n'));
  assert.ok(after.endsWith('\nsuffix\n'));
  assert.ok(after.indexOf('#9') < after.indexOf('#2'));
  assert.ok(after.includes('\\"quote\\"'));
  assert.ok(!after.includes('#3'));
  assert.equal(renderChoices(after, pulls), after);
  assert.throws(() => renderChoices('missing', pulls));
  assert.ok(!renderChoices(before, [{ number: 1, title: '${{ secrets.EXAMPLE }}' }]).includes('${{'));
});

test('diagnostic cache reuse requires matching scope and cannot authorize publication', t => {
  const root = fs.mkdtempSync(path.join(os.tmpdir(), 'ci-diagnostic-'));
  t.after(() => fs.rmSync(root, { recursive: true, force: true }));
  const file = path.join(root, 'event.json');
  const controls = normalize({ operation: 'Build', build_targets: 'Linux' });
  fs.writeFileSync(file, JSON.stringify({ inputs: controls }));
  const env = { GITHUB_EVENT_NAME: 'workflow_dispatch', GITHUB_EVENT_PATH: file };
  assert.equal(diagnosticReuseAllowed({ controls }, env), true);
  assert.equal(diagnosticReuseAllowed({ controls: { ...controls, validation_scope: 'Receipts' } }, env), false);
  assert.equal(diagnosticReuseAllowed({ controls }, { ...env, CI_PUBLICATION_JOB: 'true' }), false);
  fs.writeFileSync(file, JSON.stringify({ inputs: {} }));
  assert.equal(diagnosticReuseAllowed({ controls }, env), false);
});

test('pending receipts are restricted to publication within their originating hosted run', t => {
  const root = fs.mkdtempSync(path.join(os.tmpdir(), 'ci-pending-'));
  t.after(() => fs.rmSync(root, { recursive: true, force: true }));
  const file = path.join(root, 'event.json');
  fs.writeFileSync(file, JSON.stringify({ inputs: { operation: 'Full Run' } }));
  const env = { GITHUB_EVENT_NAME: 'workflow_dispatch', GITHUB_EVENT_PATH: file, GITHUB_ACTIONS: 'true',
    GITHUB_SERVER_URL: 'https://github.com', GITHUB_REF: 'refs/heads/source', GITHUB_ACTOR: 'admin',
    GITHUB_RUN_ID: '123', GITHUB_SHA: 'a'.repeat(40), CI_PUBLICATION_JOB: 'true' };
  const run = { id: 123, head_sha: env.GITHUB_SHA, status: 'in_progress', conclusion: null, actor: { login: 'admin' } };
  assert.equal(pendingReceiptAllowed(run, env), true);
  assert.equal(pendingReceiptAllowed(run, { ...env, GITHUB_EVENT_NAME: 'push' }), true);
  for (const patch of [{ GITHUB_RUN_ID: '124' }, { GITHUB_ACTOR: 'other' }, { CI_PUBLICATION_JOB: 'false' },
    { ACT: 'true' }, { GITHUB_SHA: 'b'.repeat(40) }]) {
    assert.equal(pendingReceiptAllowed(run, { ...env, ...patch }), false);
  }
  assert.equal(pendingReceiptAllowed({ ...run, status: 'completed', conclusion: 'failure' }, env), false);
});

test('source execution recognizes admin merges and distinguishes direct admin pushes', t => {
  const sha = 'a'.repeat(40);
  const env = { GITHUB_EVENT_NAME: 'push', GITHUB_REF: 'refs/heads/source', GITHUB_ACTIONS: 'true',
    GITHUB_SERVER_URL: 'https://github.com', GITHUB_SHA: sha, GITHUB_ACTOR: 'admin', GITHUB_REPOSITORY: 'owner/project' };
  const pr = { number: 17, merged: true, merged_at: new Date().toISOString(), merge_commit_sha: sha,
    base: { ref: 'source', repo: { full_name: 'owner/project' } }, merged_by: { login: 'admin' } };
  const clients = { isAdmin: login => login === 'admin', api: route => {
    if (route.includes('/commits/')) return [pr];
    if (route.endsWith('/pulls/17')) return pr;
    throw Error(`Unexpected API call: ${route}`);
  } };
  assert.deepEqual(sourceApproval(env, clients), { kind: 'admin-merge', actor: 'admin', merged_by: 'admin', pr: 17, source_sha: sha });
  assert.equal(sourceApproval(env, { ...clients, api: () => [] }).kind, 'admin-source-push');
  assert.equal(sourceApproval({ ...env, ACT: 'true' }, clients), null);
  assert.equal(sourceApproval({ ...env, GITHUB_REF: 'refs/heads/other' }, clients), null);
  assert.equal(sourceApproval({ ...env, GITHUB_ACTOR: 'contributor' }, clients), null);
  assert.equal(sourceApproval({ ...env, GITHUB_EVENT_NAME: 'pull_request_target' }, clients), null);
  const root = fs.mkdtempSync(path.join(os.tmpdir(), 'ci-source-approval-'));
  t.after(() => fs.rmSync(root, { recursive: true, force: true }));
  const file = path.join(root, 'event.json');
  fs.writeFileSync(file, JSON.stringify({ after: 'b'.repeat(40), ref: env.GITHUB_REF, repository: { full_name: env.GITHUB_REPOSITORY } }));
  assert.equal(sourceApproval({ ...env, GITHUB_EVENT_PATH: file }, clients), null);
  fs.writeFileSync(file, JSON.stringify({ after: sha, ref: env.GITHUB_REF, repository: { full_name: env.GITHUB_REPOSITORY } }));
  assert.equal(sourceApproval({ ...env, GITHUB_EVENT_PATH: file }, clients).kind, 'admin-merge');
  const other = { ...pr, merge_commit_sha: 'b'.repeat(40) };
  assert.equal(sourceApproval(env, { ...clients, api: () => [other] }).kind, 'admin-source-push');
});

test('manual publication requires hosted Source, an administrator and a publishing operation', t => {
  const root = fs.mkdtempSync(path.join(os.tmpdir(), 'ci-publication-'));
  t.after(() => fs.rmSync(root, { recursive: true, force: true }));
  const eventFile = path.join(root, 'event.json');
  const env = { GITHUB_EVENT_PATH: eventFile, GITHUB_EVENT_NAME: 'workflow_dispatch', GITHUB_ACTIONS: 'true',
    GITHUB_SERVER_URL: 'https://github.com', GITHUB_REF: 'refs/heads/source', GITHUB_ACTOR: 'admin' };
  fs.writeFileSync(eventFile, JSON.stringify({ inputs: { operation: 'Publish' } }));
  assert.equal(authorizePublication(env, () => true), true);
  assert.throws(() => authorizePublication(env, () => false));
  assert.throws(() => authorizePublication({ ...env, ACT: 'true' }, () => true));
  assert.throws(() => authorizePublication({ ...env, GITHUB_REF: 'refs/heads/other' }, () => true));
  fs.writeFileSync(eventFile, JSON.stringify({ inputs: { operation: 'Build' } }));
  assert.throws(() => authorizePublication(env, () => true));
});

test('gate overrides distinguish validation failures, coverage and failed builds', t => {
  const root = fs.mkdtempSync(path.join(os.tmpdir(), 'ci-gate-'));
  t.after(() => fs.rmSync(root, { recursive: true, force: true }));
  fs.mkdirSync(path.join(root, 'build/tmp/releases'), { recursive: true });
  const planFile = path.join(root, 'build/tmp/releases/plan.json');
  const eventFile = path.join(root, 'event.json');
  const gate = fileURLToPath(new URL('../gate.mjs', import.meta.url));
  function run(policy, validation, receipt = 'success', build = 'success', source = false) {
    fs.writeFileSync(eventFile, JSON.stringify({ inputs: { operation: 'Build', gate_policy: policy } }));
    fs.writeFileSync(planFile, JSON.stringify({ validation: { success: validation },
      context: source ? { source_authorization: { kind: 'admin-source-push', actor: 'admin' } } : {} }));
    const results = Object.fromEntries(['validate', 'build', 'images', 'repository', 'pages', 'release', 'validation-receipt']
      .map(name => [name, { result: name === 'build' ? build : name === 'validation-receipt' ? receipt : name === 'validate' ? 'success' : 'skipped' }]));
    return spawnSync(process.execPath, [gate], { cwd: root, encoding: 'utf8', env: { ...process.env,
      GITHUB_EVENT_NAME: source ? 'push' : 'workflow_dispatch', GITHUB_EVENT_PATH: eventFile, GITHUB_STEP_SUMMARY: '',
      RESULTS: JSON.stringify(results), ENABLED: JSON.stringify({ images: 'false', repository: 'false', pages: 'false', release: 'false' }) } });
  }
  assert.equal(run('Enforce all', true).status, 0);
  assert.notEqual(run('Enforce all', false).status, 0);
  assert.equal(run('Ignore validation failures', false).status, 0);
  assert.notEqual(run('Ignore validation failures', false, 'skipped').status, 0);
  assert.equal(run('Ignore incomplete coverage', true, 'skipped').status, 0);
  assert.equal(run('Ignore both', false, 'skipped').status, 0);
  assert.notEqual(run('Ignore both', false, 'success', 'failure').status, 0);
  assert.equal(run('Enforce all', true, 'success', 'success', true).status, 0);
  assert.notEqual(run('Enforce all', true, 'skipped', 'success', true).status, 0);
  assert.match(run('Enforce all', true, 'skipped', 'skipped', true).stderr, /Administrator-approved source run skipped required builds/);
});
