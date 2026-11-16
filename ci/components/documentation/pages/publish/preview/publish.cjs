'use strict';
// Trusted publication job: never run commands from a preview checkout.
// The artifact from Build is treated solely as untrusted static files.
const fs = require('node:fs');
const path = require('node:path');
const { spawnSync } = require('node:child_process');
const { root, settings, target, resolveTarget } = require('./config.cjs');
const { rest, update, exportSite, previewPath, assets } = require('./state.cjs');

const candidateDir = path.join(root, 'build/preview-candidate');
const combinedDir = path.join(root, 'build/preview-staged');
const productionDir = path.join(root, 'build/github/pages');

function notes(message) {
  process.stdout.write(message + '\n');
  if (process.env.GITHUB_STEP_SUMMARY)
    fs.appendFileSync(process.env.GITHUB_STEP_SUMMARY, message + '\n');
}
function aliasFromEnv(config, env) {
  if (!env.CI_PREVIEW_TARGET || !env.CI_PREVIEW_ALIAS)
    throw new Error('Missing trusted preview identity');
  const parsed = target(env.CI_PREVIEW_TARGET, config);
  if (parsed.alias !== env.CI_PREVIEW_ALIAS) throw new Error('Preview alias mismatch');
  if (!parsed.remove && !/^[a-f0-9]{40}$/.test(env.CI_PREVIEW_SHA || ''))
    throw new Error('Missing preview commit identity');
  return { ...parsed, sha: parsed.remove ? null : env.CI_PREVIEW_SHA };
}

async function verifyCandidate(candidate, config, api) {
  if (candidate.remove) return;
  const current = await resolveTarget(candidate, config, (method, resource) =>
    api(method, resource));
  if (current.sha !== candidate.sha)
    throw new Error('Preview source changed during build; refusing stale artifact');
}

function cloudflareDeploy(config, candidate, env = process.env) {
  if (candidate.remove) throw new Error(
    'Cloudflare Pages cannot reliably delete the latest branch alias deployment. ' +
    'Disable the branch or remove it in Cloudflare if available.');
  if (!env.CLOUDFLARE_API_TOKEN || !config.accountId)
    throw new Error('Configure CLOUDFLARE_API_TOKEN and CLOUDFLARE_ACCOUNT_ID ' +
      'in the protected ci-preview-cloudflare environment');
  // Validation is done before passing these values to Wrangler; no shell.
  if (!/^[a-f0-9]{32}$/.test(config.accountId))
    throw new Error('Invalid Cloudflare account ID');
  // The Cloudflare branch alias has an independent origin, but the site's
  // public URL retains the configured project path (e.g. /Template/).
  // Wrangler serves the upload directory from '/', so stage the site under
  // the desired path rather than uploading index.html to the wrong root.
  const upload = path.join(root, 'build/preview-cloudflare');
  if (fs.existsSync(upload)) {
    if (fs.lstatSync(upload).isSymbolicLink())
      throw new Error('Refusing linked Cloudflare upload directory');
    fs.rmSync(upload, { recursive: true });
  }
  const basePath = config.base.slice(1);
  const directory = path.join(upload, basePath);
  fs.mkdirSync(directory, { recursive: true });
  fs.cpSync(candidateDir, directory, { recursive: true });
  const cli = process.platform === 'win32' ? 'npx.cmd' : 'npx';
  const args = ['--yes', 'wrangler@4.47.0', 'pages', 'deploy', upload,
    '--project-name=' + config.cloudflare_project, '--branch=' + candidate.alias,
    '--commit-hash=' + candidate.sha];
  const result = spawnSync(cli, args, {
    cwd: root, stdio: 'inherit', shell: false, timeout: 600000,
    env: { ...env, CLOUDFLARE_ACCOUNT_ID: config.accountId },
  });
  if (result.error || result.status !== 0)
    throw new Error('Cloudflare Pages preview deployment failed: ' +
      (result.error?.message || result.status));
  const url = 'https://' + candidate.alias + '.' + config.cloudflare_project +
    '.pages.dev' + config.base;
  notes('Preview published: ' + url);
  return url;
}

async function publishPreview(env = process.env) {
  const config = settings(undefined, env);
  if (!config.enabled) throw new Error('Preview publishing is disabled');
  if (env.GITHUB_EVENT_NAME !== 'push' ||
      env.CI_PREVIEW_TRUSTED_SOURCE !== 'true')
    throw new Error('Only the trusted generated preview Publish job may run this command');
  const selected = aliasFromEnv(config, env);
  const api = rest(config.repo, env.GH_TOKEN, env);
  await verifyCandidate(selected, config, api);
  if (config.provider === 'cloudflare-pages')
    return cloudflareDeploy(config, selected, env);
  if (!selected.remove) assets(candidateDir, previewPath(config, selected));
  await update(config, { kind: selected.remove ? 'remove' : 'preview',
    target: selected, directory: candidateDir }, api);
  await exportSite(config, api, combinedDir);
  const url = config.site + config.base + config.path_prefix + '/' + selected.alias + '/';
  notes((selected.remove ? 'Preview removed: ' : 'Preview prepared: ') + url);
  return url;
}

function copyProduction() {
  if (!fs.existsSync(path.join(productionDir, 'index.html')))
    throw new Error('Missing production Pages artifact');
  if (fs.existsSync(combinedDir)) {
    if (fs.lstatSync(combinedDir).isSymbolicLink())
      throw new Error('Refusing linked Pages output');
    fs.rmSync(combinedDir, { recursive: true });
  }
  fs.cpSync(productionDir, combinedDir, { recursive: true });
}

async function publishProduction(env = process.env) {
  const config = settings(undefined, env);
  if (env.CI_EVENT !== 'push' || env.CI_GRAPH_RUN !== 'true' ||
      env.CI_PHASE !== 'publish' || env.GITHUB_EVENT_NAME !== 'push' ||
      !env.CI_RUN_BRANCH || !/^ci\/run-[1-9][0-9]*-[1-9][0-9]*$/.test(env.CI_RUN_BRANCH) ||
      env.GITHUB_REF !== 'refs/heads/' + env.CI_RUN_BRANCH ||
      !/^[a-f0-9]{40}$/.test(env.CI_SOURCE_SHA || ''))
    throw new Error('Production snapshot requires the trusted source Publish stage');
  if (!config.enabled || config.provider !== 'github-pages') {
    copyProduction();
    notes('Production Pages artifact staged without GitHub preview state');
    return;
  }
  const api = rest(config.repo, env.GH_TOKEN, env);
  await update(config, { kind: 'production', directory: productionDir }, api);
  await exportSite(config, api, combinedDir);
  notes('Production and active previews staged together');
}

if (require.main === module) {
  const command = process.argv[2];
  const work = command === '--preview' ? publishPreview :
    command === '--production' ? publishProduction : null;
  if (!work) { console.error('Expected --preview or --production'); process.exitCode = 2; }
  else work().catch(error => { console.error('::error::' +
    String(error.message || error)); process.exitCode = 1; });
}

module.exports = { aliasFromEnv, verifyCandidate, publishPreview,
  publishProduction, cloudflareDeploy };
