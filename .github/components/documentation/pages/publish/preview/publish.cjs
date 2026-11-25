'use strict';
const fs = require('node:fs');
const path = require('node:path');
const { spawnSync } = require('node:child_process');
const { root, settings, target, resolveTarget, workflowTarget, previewHost } = require('./config.cjs');
const { api } = require('./github.cjs');
const { syncComment, findOwned, bodyFor } = require('./comment.cjs');

const candidateDir = path.join(root, 'build/preview-candidate');
const uploadDir = path.join(root, 'build/preview-cloudflare');

function url(config, candidate) {
  return 'https://' + candidate.alias + '.' + previewHost(config) + config.base;
}
// A PR artifact is data, never a Cloudflare Worker or a configuration source.
function copyStatic(source, destination) {
  const stat = fs.lstatSync(source);
  if (!stat.isDirectory() || stat.isSymbolicLink()) throw new Error('Invalid static preview directory');
  fs.mkdirSync(destination, { recursive: true });
  for (const item of fs.readdirSync(source, { withFileTypes: true })) {
    if (/^(?:_worker\.js|_routes\.json|_headers|_redirects|functions|\.wrangler|wrangler\.(?:toml|jsonc?))$/i.test(item.name))
      throw new Error('Forbidden executable or control file in preview: ' + item.name);
    const from = path.join(source, item.name), to = path.join(destination, item.name);
    if (item.isSymbolicLink()) throw new Error('Linked preview asset');
    if (item.isDirectory()) copyStatic(from, to);
    else if (item.isFile()) fs.copyFileSync(from, to);
    else throw new Error('Non-regular preview asset');
  }
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
    copyStatic(candidateDir, dest);
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
    // Preserve the API's error code and bounded message so a failing cleanup can
    // distinguish deployment listing from deletion without logging tokens or URLs.
    const json = await response.json().catch(() => null);
    if (!response.ok || json?.success !== true) {
      const details = Array.isArray(json?.errors) ? json.errors.slice(0, 3).map(error => {
        const code = Number.isSafeInteger(error?.code) ? error.code : 'unknown';
        const message = String(error?.message || '').replace(/[\x00-\x1f\x7f]/g, ' ').slice(0, 250);
        return code + (message ? ': ' + message : '');
      }).join('; ') : '';
      throw new Error('Cloudflare cleanup ' + method + ' HTTP ' + response.status +
        (details ? ' (' + details + ')' : ' (no API error details)'));
    }
    return json;
  }
  const matching = [];
  for (let page = 1; page <= 30; page++) {
    const response = await call(base + '?env=preview&per_page=25&page=' + page, 'GET');
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

// Verify the configured public hostname against Cloudflare before deployment.
async function verifyProjectHost(config, env, request = fetch) {
  const endpoint = 'https://api.cloudflare.com/client/v4/accounts/' + config.accountId +
    '/pages/projects/' + config.cloudflare_project;
  const response = await request(endpoint, { headers: {
    Authorization: 'Bearer ' + env.CLOUDFLARE_API_TOKEN, Accept: 'application/json',
  }, signal: AbortSignal.timeout(30000) });
  if (!response.ok) throw new Error('Cloudflare project lookup HTTP ' + response.status);
  const payload = await response.json();
  if (payload.success !== true || typeof payload.result?.subdomain !== 'string')
    throw new Error('Cloudflare did not return the project public hostname');
  const actual = previewHost({ ...config, cloudflare_domain: payload.result.subdomain });
  if (actual !== previewHost(config))
    throw new Error('Set github.previews.cloudflare_domain to ' + actual + ' before publishing');
  return actual;
}
async function cloudflareDeploy(config, candidate, env = process.env) {
  if (!env.CLOUDFLARE_API_TOKEN || !/^[0-9a-f]{32}$/i.test(config.accountId))
    throw new Error('Configure CLOUDFLARE_API_TOKEN and CLOUDFLARE_ACCOUNT_ID in ci-preview-cloudflare');
  await verifyProjectHost(config, env);
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
async function publishNative(env = process.env, deploy = cloudflareDeploy, request = api, comment = syncComment) {
  if (env.GITHUB_ACTIONS !== 'true' || env.GITHUB_EVENT_NAME !== 'workflow_run' ||
      !/^[1-9][0-9]{0,8}$/.test(env.PR_NUMBER || '') ||
      !/^[a-f0-9]{40}$/.test(env.REQUEST_SHA || '') || !env.CI_DEFAULT_BRANCH)
    throw new Error('Preview requires a trusted completed CI run');
  const config = settings(undefined, env);
  if (!config.enabled || !config.pull_requests) return null;
  const pr = await request('GET', '/repos/' + config.repo + '/pulls/' + env.PR_NUMBER, env.GH_TOKEN);
  if (pr.state !== 'open' || String(pr.number) !== env.PR_NUMBER ||
      pr.base?.repo?.full_name !== config.repo || pr.base.ref !== config.defaultBranch ||
      pr.head?.repo?.full_name !== config.repo || pr.head.sha !== env.REQUEST_SHA) {
    console.log('PR no longer matches; preview skipped');
    return null;
  }
  const candidate = { ...target('pr:' + env.PR_NUMBER, config), sha: env.REQUEST_SHA };
  const result = await deploy(config, candidate, env);
  await comment(config, candidate, env, false, request);
  return result;
}
function manualContext(env) {
  if (env.GITHUB_ACTIONS !== 'true' || env.GITHUB_EVENT_NAME !== 'workflow_dispatch' ||
      !env.CI_DEFAULT_BRANCH || env.GITHUB_REF !== 'refs/heads/' + env.CI_DEFAULT_BRANCH ||
      env.ACT === 'true') throw new Error('Manual previews require the trusted default branch');
  const config = settings(undefined, env);
  if (!config.enabled) throw new Error('Previews disabled');
  const requested = workflowTarget(JSON.parse(env.PREVIEW_INPUTS || '{}'));
  return { config, requested, candidate: target(requested, config) };
}
async function resolveManual(env = process.env, request = api) {
  const { config, requested, candidate } = manualContext(env);
  const resolved = await resolveTarget(candidate, config, (method, resource) => request(method, resource, env.GH_TOKEN));
  return { requested, sha: resolved.sha || '', remove: String(resolved.remove), alias: resolved.alias,
    base: config.base, site: 'https://' + resolved.alias + '.' + previewHost(config) };
}
async function publishManual(env = process.env, deploy = cloudflareDeploy, request = api, comment = syncComment) {
  const { config, requested, candidate } = manualContext(env);
  if (requested !== env.PREVIEW_TARGET || candidate.alias !== env.PREVIEW_ALIAS)
    throw new Error('Resolved preview target mismatch');
  const verified = await resolveTarget(candidate, config, (method, resource) => request(method, resource, env.GH_TOKEN));
  if ((verified.sha || '') !== (env.REQUEST_SHA || '')) throw new Error('Preview revision changed while building');
  const result = await deploy(config, verified, env);
  if (candidate.type === 'pr') await comment(config, verified, env, candidate.remove, request);
  return result;
}
async function retireClosed(env = process.env, request = api) {
  if (env.GITHUB_ACTIONS !== 'true' || env.GITHUB_EVENT_NAME !== 'workflow_run' ||
      !/^[1-9][0-9]{0,8}$/.test(env.PR_NUMBER || '') ||
      !/^[a-f0-9]{40}$/.test(env.REQUEST_SHA || '') || !env.CI_DEFAULT_BRANCH)
    throw new Error('Retirement requires a trusted resolved PR closure');
  const config = settings(undefined, env);
  if (!config.enabled || !config.pull_requests) return null;
  const number = env.PR_NUMBER;
  const pr = await request('GET', '/repos/' + config.repo + '/pulls/' + number, env.GH_TOKEN);
  if (pr.state !== 'closed' || String(pr.number) !== number ||
      pr.base?.repo?.full_name !== config.repo || pr.base.ref !== env.CI_DEFAULT_BRANCH ||
      pr.head?.repo?.full_name !== config.repo || pr.head.sha !== env.REQUEST_SHA) {
    console.log('PR closure no longer matches; retirement skipped');
    return null;
  }
  const candidate = target('delete:pr:' + number, config);
  const previous = await findOwned(config, candidate, env, request);
  if (!previous) { console.log('No published PR preview to retire'); return null; }
  if (previous.body === bodyFor(config, candidate, true)) {
    console.log('PR preview is already retired'); return null;
  }
  const removed = await cloudflareDeploy(config, candidate, env);
  const note = await syncComment(config, candidate, env, true, request);
  if (note) console.log('::notice::PR preview comment ' + note.action);
  return removed;
}
module.exports = { copyStatic, prepareUpload, verifyProjectHost, cloudflareDeploy, pruneRetired, publishNative, resolveManual, publishManual, retireClosed };
if (require.main === module) {
  const command = process.argv[2], handler = command === '--manual-resolve'
    ? async () => { for (const [key, value] of Object.entries(await resolveManual())) fs.appendFileSync(process.env.GITHUB_OUTPUT, key + '=' + value + '\n'); }
    : command === '--manual' ? publishManual : command === '--retire' ? retireClosed : command === '--native' ? publishNative : null;
  if (!handler) { console.error('Expected --native, --manual-resolve, --manual or --retire'); process.exitCode = 2; }
  else Promise.resolve().then(() => handler()).catch(e => {
    console.error('::error::' + e.message); process.exitCode = 1;
  });
}
