'use strict';
// Trusted source dispatch -> generated workflow. The candidate builds without
// credentials. The publisher checks out the trusted source and reads static assets.
const fs = require('node:fs');
const { settings, target, sourceContext, resolveTarget } = require('./config.cjs');
const { api, writerToken, createBranch, observe } = require('../../../../../github/workflows/launch.cjs');
const SHA = /^[a-f0-9]{40}$/;
const expression = x => '$' + '{{ ' + x + ' }}';

function render(ctx, candidate, config) {
  const cloudflare = config.provider === 'cloudflare-pages';
  const host = cloudflare ? 'https://' + candidate.alias + '.' +
    config.cloudflare_project + '.pages.dev' : config.site;
  const base = cloudflare ? config.base :
    config.base + config.path_prefix + '/' + candidate.alias + '/';
  const publishSteps = [
    { uses: 'actions/checkout@v7',
      with: { ref: ctx.sha, 'persist-credentials': false } },
    { uses: 'actions/setup-node@v7.1.0', with: { 'node-version': '24' } },
    ...(candidate.remove ? [] : [
      { uses: 'actions/download-artifact@v8',
        with: { name: 'preview-site', path: 'build/preview-candidate' } },
    ]),
    { name: 'Prepare preview publication',
      env: {
        GH_TOKEN: expression('github.token'),
        CI_PREVIEW_TRUSTED_SOURCE: 'true',
        CI_PREVIEW_TARGET: ctx.target,
        CI_PREVIEW_ALIAS: candidate.alias,
        CI_PREVIEW_SHA: candidate.sha || '',
        ...(cloudflare ? {
          CLOUDFLARE_API_TOKEN: expression('secrets.CLOUDFLARE_API_TOKEN'),
          CLOUDFLARE_ACCOUNT_ID: expression('vars.CLOUDFLARE_ACCOUNT_ID'),
        } : {}),
      },
      run: 'node ci/components/documentation/pages/preview/publish.cjs --preview',
    },
  ];
  if (!cloudflare) publishSteps.push(
    { name: 'Upload combined GitHub Pages artifact',
      uses: 'actions/upload-pages-artifact@v4',
      with: { path: 'build/preview-staged' } },
    { name: 'Deploy combined Pages site', id: 'deployment',
      uses: 'actions/deploy-pages@v4' },
  );
  const jobs = {
    ...(candidate.remove ? {} : {
      build: {
        name: 'Preview / Build (unprivileged)',
        'runs-on': 'ubuntu-latest', permissions: { contents: 'read' },
        steps: [
          { uses: 'actions/checkout@v7',
            with: { ref: candidate.sha, 'persist-credentials': false } },
          { uses: 'actions/setup-node@v7.1.0', with: { 'node-version': '24' } },
          { name: 'Generate static documentation', env: {
            DOCS_BASE: base, DOCS_SITE: host,
          }, run: 'node ci/components/documentation/pages/build/starlight/build.cjs' },
          { name: 'Preserve static preview only',
            uses: 'actions/upload-artifact@v7',
            with: { name: 'preview-site', path: 'build/github/pages/',
              'if-no-files-found': 'error',
              'retention-days': config.retention_days } },
        ],
      },
    }),
    publish: {
      name: 'Preview / Publish (trusted)',
      'runs-on': 'ubuntu-latest',
      ...(candidate.remove ? {} : { needs: ['build'] }),
      permissions: cloudflare ? { contents: 'read' } :
        { contents: 'write', pages: 'write', 'id-token': 'write' },
      environment: cloudflare ? { name: 'ci-preview-cloudflare' } :
        { name: 'github-pages', url: expression('steps.deployment.outputs.page_url') },
      steps: publishSteps,
    },
  };
  return { 'pipeline.yml': '# Generated from trusted source; do not edit.\n' +
    JSON.stringify({ name: 'Preview', 'run-name': 'preview ' + candidate.alias,
      on: { push: { branches: [ctx.branch] } },
      permissions: {}, jobs }, null, 2) + '\n' };
}

async function deleteGenerated(ctx, expected, token, env) {
  const expectedName = 'ci/preview-' + env.GITHUB_RUN_ID + '-' +
    env.GITHUB_RUN_ATTEMPT + '-' + ctx.sha.slice(0, 10);
  if (ctx.branch !== expectedName || !SHA.test(expected))
    throw new Error('Refusing unrelated preview branch cleanup');
  const ref = '/repos/' + ctx.repo + '/git/ref/heads/' + ctx.branch;
  let current;
  try { current = await api('GET', ref, token, undefined, env); }
  catch (error) { if (String(error.message).includes('HTTP 404')) return; throw error; }
  if (current.object?.sha !== expected)
    throw new Error('Preview execution ref changed; refusing to delete');
  await api('DELETE', '/repos/' + ctx.repo + '/git/refs/heads/' + ctx.branch,
    token, undefined, env);
  console.log('::notice::Removed generated preview branch ' + ctx.branch);
}

async function run(env = process.env) {
  const context = sourceContext(env);
  const config = settings(undefined, env);
  if (!config.enabled) throw new Error('Previews are disabled in targets.toml');
  const candidate = target(context.target, config);
  if (config.provider === 'cloudflare-pages' && candidate.remove)
    throw new Error('Cloudflare cannot delete the latest alias. Use provider controls.');
  const reader = env.GH_TOKEN;
  if (!reader) throw new Error('Missing read-only GitHub token');
  const selected = await resolveTarget(candidate, config,
    (method, resource) => api(method, resource, reader, undefined, env));
  const ctx = { repo: config.repo, sha: context.sourceSha, target: context.target,
    branch: 'ci/preview-' + context.runId + '-' + context.attempt +
      '-' + context.sourceSha.slice(0, 10) };
  const workflows = render(ctx, selected, config);
  const auth = { ...env,
    CI_NATIVE_APP_ID: env.CI_CREDENTIAL_APP_ID,
    CI_NATIVE_APP_PRIVATE_KEY: env.CI_CREDENTIAL_APP_PRIVATE_KEY,
    CI_NATIVE_WRITE_TOKEN: env.CI_CREDENTIAL_BOOTSTRAP_TOKEN,
    CI_NATIVE_READ_TOKEN: reader };
  const writer = await writerToken(ctx.repo, auth);
  const revision = await createBranch(ctx, workflows, writer, env);
  let failure;
  try {
    const result = await observe(ctx, revision, reader, env);
    const url = config.provider === 'github-pages'
      ? config.site + config.base + config.path_prefix + '/' + selected.alias + '/'
      : 'https://' + selected.alias + '.' + config.cloudflare_project +
        '.pages.dev' + config.base;
    if (env.GITHUB_STEP_SUMMARY) fs.appendFileSync(env.GITHUB_STEP_SUMMARY,
      '\n### Documentation preview\n\nTarget: ' + context.target +
      '\n\nURL: ' + url + '\n\nGenerated run: ' + result.link + '\n');
    console.log('::notice::Preview publication succeeded: ' + url);
    return { ...selected, url };
  } catch (error) {
    failure = error; throw error;
  } finally {
    try { await deleteGenerated(ctx, revision, writer, env); }
    catch (error) {
      if (failure) console.error('::error::Preview cleanup also failed: ' + error.message);
      else throw error;
    }
  }
}

module.exports = { render, deleteGenerated, run };
if (require.main === module)
  run().catch(e => { console.error('::error::' + e.message); process.exitCode = 1; });
