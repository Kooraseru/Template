'use strict';
// Persist production and branch previews in one orphan branch. GitHub Pages
// accepts a single deployment per repository, so every deploy is a snapshot.
const fs = require('node:fs');
const path = require('node:path');

const SHA = /^[0-9a-f]{40}$/;
const MAX_FILES = 4000;
const MAX_BYTES = 48 * 1024 * 1024;

class HttpError extends Error {
  constructor(method, resource, status, detail = '') {
    super(method + ' ' + resource + ' returned HTTP ' + status + ' ' + detail.slice(0, 140));
    this.status = status;
  }
}

function rest(repo, token, env = process.env) {
  if (!token) throw new Error('Missing GitHub state write token');
  const origin = new URL(env.GITHUB_API_URL || 'https://api.github.com');
  if (origin.protocol !== 'https:' || origin.username || origin.password)
    throw new Error('Expected a trusted HTTPS GitHub API');
  const base = origin.toString().replace(/\/+$/, '') + '/repos/' + repo;
  return async function request(method, resource, body) {
    const response = await fetch(base + resource, {
      method, headers: {
        Authorization: 'Bearer ' + token, Accept: 'application/vnd.github+json',
        'Content-Type': 'application/json', 'X-GitHub-Api-Version': '2022-11-28',
        'User-Agent': 'Template-Preview-Publisher',
      },
      body: body === undefined ? undefined : JSON.stringify(body),
      signal: AbortSignal.timeout(30000),
    });
    const text = await response.text();
    if (!response.ok) throw new HttpError(method, resource, response.status, text);
    return text ? JSON.parse(text) : {};
  };
}

function assets(root, prefix) {
  if (!fs.existsSync(root) || fs.lstatSync(root).isSymbolicLink() || !fs.statSync(root).isDirectory())
    throw new Error('Preview assets must be a regular directory');
  const list = [];
  let bytes = 0;
  function visit(folder, relative = '') {
    for (const item of fs.readdirSync(folder, { withFileTypes: true })) {
      if (item.isSymbolicLink()) throw new Error('Refusing symlinked site asset');
      if (item.name === '.git' || item.name === '..') throw new Error('Invalid site asset name');
      const here = path.join(folder, item.name);
      const dest = relative ? relative + '/' + item.name : item.name;
      if (dest.split('/').includes('..') || dest.includes('\\'))
        throw new Error('Unsafe static asset path');
      if (item.isDirectory()) visit(here, dest);
      else if (item.isFile()) {
        if (prefix === 'site/' && dest.startsWith('previews/'))
          throw new Error('Production assets cannot overwrite preview paths');
        const size = fs.statSync(here).size;
        bytes += size;
        if (bytes > MAX_BYTES || list.length >= MAX_FILES)
          throw new Error('Preview site exceeds configured storage limits');
        list.push({ path: prefix + dest, bytes: fs.readFileSync(here) });
      } else throw new Error('Unsupported site asset type');
    }
  }
  visit(root);
  if (!list.some(x => x.path === prefix + 'index.html'))
    throw new Error('Static site has no index.html');
  return list;
}

async function refState(request, name) {
  let ref;
  try { ref = await request('GET', '/git/ref/heads/' + name); }
  catch (error) { if (error.status === 404) return null; throw error; }
  if (!SHA.test(ref.object?.sha || '')) throw new Error('Invalid preview state ref');
  const commit = await request('GET', '/git/commits/' + ref.object.sha);
  const tree = await request('GET', '/git/trees/' + commit.tree.sha + '?recursive=1');
  if (tree.truncated || !Array.isArray(tree.tree) || tree.tree.length > MAX_FILES)
    throw new Error('Preview state tree is too large or truncated');
  const blobs = tree.tree.filter(x => x.type === 'blob');
  if (blobs.some(x => x.mode !== '100644' || !SHA.test(x.sha) || !/^site\/|^manifest\.json$/.test(x.path)))
    throw new Error('Preview state contains unexpected files');
  return { head: ref.object.sha, tree: commit.tree.sha, blobs };
}

async function getBlob(request, sha) {
  const blob = await request('GET', '/git/blobs/' + sha);
  if (blob.encoding !== 'base64' || typeof blob.content !== 'string')
    throw new Error('Invalid GitHub blob response');
  return Buffer.from(blob.content.replace(/\s/g, ''), 'base64');
}

async function readManifest(request, previous) {
  const entry = previous?.blobs.find(x => x.path === 'manifest.json');
  if (!entry) return { version: 1, previews: {} };
  const parsed = JSON.parse((await getBlob(request, entry.sha)).toString('utf8'));
  if (parsed.version !== 1 || typeof parsed.previews !== 'object' || Array.isArray(parsed.previews))
    throw new Error('Invalid stored preview manifest');
  return parsed;
}

function previewPath(config, candidate) {
  if (!/^[a-z0-9][a-z0-9-]{1,75}$/.test(candidate.alias)) throw new Error('Unsafe preview alias');
  return 'site/' + config.path_prefix + '/' + candidate.alias + '/';
}

function removals(old, prefix) {
  return old.filter(item => item.path.startsWith(prefix))
    .map(item => ({ path: item.path, mode: '100644', type: 'blob', sha: null }));
}

async function update(config, change, request, now = Date.now()) {
  const id = change?.target?.alias;
  if (change.kind !== 'production' && !id) throw new Error('Missing preview identity');
  const production = change.kind === 'production';
  const prefix = production ? 'site/' : previewPath(config, change.target);
  const local = change.kind === 'remove' ? [] : assets(change.directory, prefix);
  for (let attempt = 0; attempt < 4; attempt++) {
    const previous = await refState(request, config.state_branch);
    if (!previous && !production)
      throw new Error('Preview state is not initialized. Publish production Pages once first.');
    const currentManifest = await readManifest(request, previous);
    const next = { version: 1, previews: { ...currentManifest.previews } };
    const expired = [];
    for (const [alias, record] of Object.entries(next.previews)) {
      if (!/^[a-z0-9][a-z0-9-]{1,75}$/.test(alias) ||
          typeof record !== 'object' || typeof record.expires !== 'number')
        throw new Error('Invalid persisted preview manifest entry');
      if (record.expires <= now) { expired.push(alias); delete next.previews[alias]; }
    }
    if (!production) {
      if (change.kind === 'remove') delete next.previews[id];
      else next.previews[id] = {
        type: change.target.type, source: change.target.type === 'pr'
          ? 'pr:' + change.target.number : 'branch:' + change.target.name,
        sha: change.target.sha, deployed: now, expires: now + config.retention_days * 86400000,
      };
    }

    const entries = [];
    for (const alias of expired) entries.push(...removals(previous.blobs,
      'site/' + config.path_prefix + '/' + alias + '/'));
    if (previous) {
      const owned = previous.blobs.filter(item =>
        production ? item.path.startsWith('site/') &&
          !item.path.startsWith('site/' + config.path_prefix + '/')
          : item.path.startsWith(prefix));
      entries.push(...owned.map(item =>
        ({ path: item.path, type: 'blob', mode: '100644', sha: null })));
    }
    // All state metadata remains outside the deployed site.
    const manifest = Buffer.from(JSON.stringify(next, null, 2) + '\n', 'utf8');
    const nextFiles = [...local, { path: 'manifest.json', bytes: manifest }];
    const hashes = await Promise.all(nextFiles.map(async file => {
      const blob = await request('POST', '/git/blobs', {
        content: file.bytes.toString('base64'), encoding: 'base64',
      });
      if (!SHA.test(blob.sha || '')) throw new Error('Invalid uploaded Git blob SHA');
      return { path: file.path, type: 'blob', mode: '100644', sha: blob.sha };
    }));
    // Deletions and replacements of the same path in one tree are undefined.
    const replaced = new Set(hashes.map(x => x.path));
    const changes = [...entries.filter(x => !replaced.has(x.path)), ...hashes];
    const tree = await request('POST', '/git/trees', {
      ...(previous ? { base_tree: previous.tree } : {}), tree: changes,
    });
    const commit = await request('POST', '/git/commits', {
      message: production ? 'docs(preview): refresh production snapshot' :
        'docs(preview): ' + (change.kind === 'remove' ? 'remove ' : 'publish ') + id,
      tree: tree.sha, parents: previous ? [previous.head] : [],
    });
    try {
      if (previous) await request('PATCH', '/git/refs/heads/' + config.state_branch,
        { sha: commit.sha, force: false });
      else await request('POST', '/git/refs',
        { ref: 'refs/heads/' + config.state_branch, sha: commit.sha });
      return { sha: commit.sha, manifest: next };
    } catch (error) {
      if (![409, 422].includes(error.status) || attempt === 3) throw error;
    }
  }
  throw new Error('Could not update Pages preview state');
}

async function exportSite(config, request, destination) {
  const state = await refState(request, config.state_branch);
  if (!state) throw new Error('Missing Pages state');
  fs.rmSync(destination, { recursive: true, force: true });
  fs.mkdirSync(destination, { recursive: true });
  let total = 0;
  const site = state.blobs.filter(x => x.path.startsWith('site/'));
  for (const file of site) {
    const relative = file.path.slice(5);
    if (!relative || relative.startsWith('/') || relative.split('/').includes('..'))
      throw new Error('Unsafe stored path');
    const data = await getBlob(request, file.sha);
    total += data.length;
    if (total > MAX_BYTES * 4) throw new Error('Combined Pages site exceeds storage budget');
    const output = path.join(destination, relative);
    fs.mkdirSync(path.dirname(output), { recursive: true });
    fs.writeFileSync(output, data);
  }
  if (!fs.existsSync(path.join(destination, 'index.html')))
    throw new Error('Combined Pages site has no production homepage');
  return site.length;
}

module.exports = { HttpError, rest, assets, refState, update, exportSite, previewPath };
