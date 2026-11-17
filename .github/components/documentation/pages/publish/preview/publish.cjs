'use strict';
const fs = require('node:fs');
const path = require('node:path');
const { spawnSync } = require('node:child_process');
const { root, settings, target, resolveTarget } = require('./config.cjs');
const { api } = require('../../../../../../ci/github/workflows/launch.cjs');
const { syncComment } = require('./comment.cjs');

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
// Cloudflare's latest branch deployment cannot be deleted. After publishing a
// 410 replacement, remove older immutable deployments from this exact alias.
async function pruneRetired(config, candidate, env, request = fetch) {
  if (!candidate.remove) return 0;
  const base = 'https://api.cloudflare.com/client/v4/accounts/' + config.accountId +
    '/pages/projects/' + config.cloudflare_project + '/deployments';
  const headers = { Authorization: 'Bearer ' + env.CLOUDFLARE_API_TOKEN,
    Accept: 'application/json' };
  async function call(url, method) {
    const response = await request(url, { method, headers, signal: AbortSignal.timeout(30000) });
    if (!response.ok) throw new Error('Cloudflare cleanup HTTP ' + response.status);
    const json = await response.json();
    if (json.success !== true) throw new Error('Cloudflare cleanup API returned failure');
    return json;
  }
  const matching = [];
  for (let page = 1; page <= 30; page++) {
    const response = await call(base + '?env=preview&per_page=100&page=' + page, 'GET');
    if (!Array.isArray(response.result)) throw new Error('Invalid Cloudflare deployment list');
    matching.push(...response.result.filter(record =>
      record.environment === 'preview' &&
      record.deployment_trigger?.metadata?.branch === candidate.alias));
    if (page >= (response.result_info?.total_pages || 1)) break;
    if (page === 30) throw new Error('Cloudflare deployment listing exceeds cleanup page limit');
  }
  matching.sort((a, b) => Date.parse(b.created_on) - Date.parse(a.created_on));
  if (matching.length === 0)
    throw new Error('Cloudflare did not list the newly retired alias deployment');
  // Keep the newest successful 410 deployment. Deleting it is prohibited by Pages.
  let removed = 0;
  for (const older of matching.slice(1)) {
    if (!/^[0-9a-f]{8}-[0-9a-f-]{27,36}$/i.test(older.id || ''))
      throw new Error('Invalid Cloudflare deployment ID');
    await call(base + '/' + older.id + '?force=true', 'DELETE');
    removed++;
  }
  return removed;
}

async function cloudflareDeploy(config, candidate, env = process.env) {
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
  if (candidate.remove) {
    const removed = await pruneRetired(config, candidate, env);
    console.log('::notice::Deleted ' + removed + ' older preview deployments');
  }
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
  const published = await cloudflareDeploy(config, candidate, env);
  if (candidate.type === 'pr') {
    const note = await syncComment(config, candidate, env, candidate.remove);
    if (note) console.log('::notice::PR preview comment ' + note.action);
  }
  return published;
}
async function retireClosed(env = process.env) {
  if (env.GITHUB_ACTIONS !== 'true' || env.GITHUB_EVENT_NAME !== 'pull_request_target' ||
      !env.GITHUB_EVENT_PATH)
    throw new Error('Retirement requires a trusted PR close event');
  const event = JSON.parse(fs.readFileSync(env.GITHUB_EVENT_PATH, 'utf8'));
  const config = settings(undefined, env);
  const number = String(event.pull_request?.number || '');
  if (event.action !== 'closed' || !Number.isSafeInteger(event.pull_request?.number) || event.pull_request.number < 1 ||
      (env.CI_PREVIEW_CLOSED_NUMBER && number !== env.CI_PREVIEW_CLOSED_NUMBER) ||
      event.repository?.full_name !== config.repo ||
      event.pull_request?.base?.repo?.full_name !== config.repo)
    throw new Error('Invalid preview close event');
  if (event.pull_request?.head?.repo?.full_name !== config.repo) return null;
  if (!config.enabled || !config.pull_requests) return null;
  const candidate = target('delete:pr:' + number, config);
  const removed = await cloudflareDeploy(config, candidate, env);
  const note = await syncComment(config, candidate, env, true);
  if (note) console.log('::notice::PR preview comment ' + note.action);
  return removed;
}
module.exports = { selected, prepareUpload, cloudflareDeploy, pruneRetired, publishPreview, retireClosed };
if (require.main === module) {
  const command = process.argv[2], handler = command === '--preview'
    ? publishPreview : command === '--retire' ? retireClosed : null;
  if (!handler) { console.error('Expected --preview or --retire'); process.exitCode = 2; }
  else Promise.resolve().then(() => handler()).catch(e => {
    console.error('::error::' + e.message); process.exitCode = 1;
  });
}
