'use strict';
const fs = require('node:fs');
const path = require('node:path');
const { spawnSync } = require('node:child_process');
const { root, settings, target, resolveTarget } = require('./config.cjs');
const { api } = require('../../../../../github/workflows/launch.cjs');

const candidateDir = path.join(root, 'build/preview-candidate');
const uploadDir = path.join(root, 'build/preview-cloudflare');

function selected(env, config) {
  const candidate = target(env.CI_PREVIEW_TARGET || '', config);
  if (candidate.alias !== env.CI_PREVIEW_ALIAS) throw new Error('Preview alias mismatch');
  if (!candidate.remove && !/^[0-9a-f]{40}$/.test(env.CI_PREVIEW_SHA || ''))
    throw new Error('Invalid preview SHA');
  return { ...candidate, sha: candidate.remove ? null : env.CI_PREVIEW_SHA };
}
function url(config, candidate) {
  return 'https://' + candidate.alias + '.' + config.cloudflare_project + '.pages.dev' + config.base;
}
function prepareUpload(config, candidate) {
  if (fs.existsSync(uploadDir)) {
    if (fs.lstatSync(uploadDir).isSymbolicLink()) throw new Error('Linked upload directory');
    fs.rmSync(uploadDir, { recursive: true });
  }
  fs.mkdirSync(uploadDir, { recursive: true });
  if (candidate.remove) {
    // Cloudflare cannot delete the latest branch deployment. Retire its alias
    // with a Worker that returns HTTP 410 for every path.
    fs.writeFileSync(path.join(uploadDir, '_worker.js'),
      'export default { async fetch() { return new Response("Preview closed", ' +
      '{ status: 410, headers: { "Cache-Control": "no-store", ' +
      '"X-Robots-Tag": "noindex", "Content-Type": "text/plain; charset=utf-8" } }); } };\n');
    fs.writeFileSync(path.join(uploadDir, 'index.html'),
      '<!doctype html><html><head><title>Preview closed</title></head><body>Preview closed</body></html>');
  } else {
    if (!fs.existsSync(path.join(candidateDir, 'index.html')) ||
        fs.lstatSync(candidateDir).isSymbolicLink())
      throw new Error('Missing static preview homepage');
    const dest = path.join(uploadDir, config.base.slice(1));
    fs.mkdirSync(dest, { recursive: true });
    fs.cpSync(candidateDir, dest, { recursive: true });
  }
  return uploadDir;
}
function cloudflareDeploy(config, candidate, env = process.env) {
  if (!env.CLOUDFLARE_API_TOKEN || !/^[0-9a-f]{32}$/i.test(config.accountId))
    throw new Error('Configure CLOUDFLARE_API_TOKEN and CLOUDFLARE_ACCOUNT_ID in ci-preview-cloudflare');
  const dest = prepareUpload(config, candidate);
  const program = process.platform === 'win32' ? 'npx.cmd' : 'npx';
  const args = ['--yes', 'wrangler@4.47.0', 'pages', 'deploy', dest,
    '--project-name=' + config.cloudflare_project,
    '--branch=' + candidate.alias,
    '--commit-hash=' + (candidate.sha || env.GITHUB_SHA)];
  const result = spawnSync(program, args, {
    cwd: root, env, stdio: 'inherit', shell: false, timeout: 600000,
  });
  if (result.error || result.status !== 0)
    throw new Error('Cloudflare deployment failed: ' + (result.error?.message || result.status));
  const label = candidate.remove ? 'Retired preview alias: ' : 'Published preview: ';
  console.log('::notice::' + label + url(config, candidate));
  if (env.GITHUB_STEP_SUMMARY)
    fs.appendFileSync(env.GITHUB_STEP_SUMMARY, '\n' + label + url(config, candidate) + '\n');
  return url(config, candidate);
}
async function publishPreview(env = process.env) {
  if (env.GITHUB_EVENT_NAME !== 'push' || env.CI_PREVIEW_TRUSTED_SOURCE !== 'true')
    throw new Error('Only trusted generated preview publisher may execute');
  const config = settings(undefined, env);
  if (!config.enabled) throw new Error('Previews disabled');
  const candidate = selected(env, config);
  if (!candidate.remove) {
    if (!env.GH_TOKEN) throw new Error('Missing GitHub read token');
    const verified = await resolveTarget(candidate, config,
      (method, endpoint) => api(method, endpoint, env.GH_TOKEN, undefined, env));
    if (verified.sha !== candidate.sha)
      throw new Error('Preview changed while building; retry dispatch');
  }
  return cloudflareDeploy(config, candidate, env);
}
async function retireClosed(env = process.env) {
  if (env.GITHUB_ACTIONS !== 'true' || env.GITHUB_EVENT_NAME !== 'pull_request_target' ||
      !env.GITHUB_EVENT_PATH || !env.CI_PREVIEW_CLOSED_NUMBER)
    throw new Error('Retirement requires a trusted PR close event');
  const event = JSON.parse(fs.readFileSync(env.GITHUB_EVENT_PATH, 'utf8'));
  const config = settings(undefined, env);
  const number = String(event.pull_request?.number || '');
  if (event.action !== 'closed' || number !== env.CI_PREVIEW_CLOSED_NUMBER ||
      event.repository?.full_name !== config.repo ||
      event.pull_request?.base?.repo?.full_name !== config.repo)
    throw new Error('Invalid preview close event');
  if (event.pull_request?.head?.repo?.full_name !== config.repo) return null;
  if (!config.enabled || !config.pull_requests) return null;
  return cloudflareDeploy(config, target('delete:pr:' + number, config), env);
}
module.exports = { selected, prepareUpload, cloudflareDeploy, publishPreview, retireClosed };
if (require.main === module) {
  const command = process.argv[2], handler = command === '--preview'
    ? publishPreview : command === '--closed' ? retireClosed : null;
  if (!handler) { console.error('Expected --preview or --closed'); process.exitCode = 2; }
  else Promise.resolve().then(() => handler()).catch(e => {
    console.error('::error::' + e.message); process.exitCode = 1;
  });
}
