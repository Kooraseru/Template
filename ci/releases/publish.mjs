import fs from 'node:fs';
import { isExecutable } from './render.mjs';
import { authorizePublication } from '../control/publication.mjs';
import path from 'node:path';
import { sha256, canonical, policy, protectionsValid, verifiedProtections, parseVersion, relative } from './core.mjs';

export function client(token, repository, fetcher = fetch) {
  const base = `https://api.github.com/repos/${repository}`;
  async function request(route, options = {}) {
    const { binary, missing, ...fetchOptions } = options;
    const url = route.startsWith('https://') ? route : base + route;
    if (!/^https:\/\/(api|uploads)\.github\.com\//.test(url)) throw Error('Unexpected GitHub API host');
    for (let attempt = 0; attempt < policy.retry_attempts; attempt++) {
      const response = await fetcher(url, { ...fetchOptions, headers: {
        Accept: 'application/vnd.github+json', Authorization: `Bearer ${token}`,
        'X-GitHub-Api-Version': '2022-11-28', ...(options.headers || {}),
      } });
      if (response.status === 404 && missing) return null;
      if (!response.ok) {
        if (response.status >= 500 && ['GET', 'PATCH', 'DELETE'].includes(options.method || 'GET') && attempt + 1 < policy.retry_attempts) {
          await new Promise(resolve => setTimeout(resolve, 1000 * (attempt + 1))); continue;
        }
        throw Error(`GitHub ${options.method || 'GET'} ${route}: ${response.status} ${await response.text()}`);
      }
      return response.status === 204 ? null : binary ? Buffer.from(await response.arrayBuffer()) : response.json();
    }
  }
  const json = (method, route, value) => request(route, { method, body: JSON.stringify(value), headers: { 'Content-Type': 'application/json' } });
  async function pages(route) {
    const entries = [];
    for (let page = 1; ; page++) {
      const result = await request(`${route}${route.includes('?') ? '&' : '?'}per_page=100&page=${page}`);
      entries.push(...result);
      if (result.length < 100) return entries;
    }
  }
  return { request, json, pages };
}
export async function protect(repository, api) {
  api ||= client(process.env.GH_TOKEN, repository);
  const summaries = await api.pages('/rulesets');
  const live = await Promise.all(summaries.map(set => api.request(`/rulesets/${set.id}`)));
  const attestation = process.env.CI_SOURCE_PROTECTION ? JSON.parse(process.env.CI_SOURCE_PROTECTION) : null;
  const rulesets = verifiedProtections(live, attestation, repository);
  if (!protectionsValid(rulesets)) throw Error('Official publication requires source PR/check protections and administrator-only updates or bypass. See ci/releases/README.md.');
  return true;
}
async function tagCommit(api, ref) {
  let object = ref?.object;
  for (let depth = 0; object?.type === 'tag' && depth < 16; depth++) {
    object = (await api.request(`/git/tags/${object.sha}`)).object;
  }
  if (object?.type && object.type !== 'commit') throw Error('Version tag does not resolve to a commit');
  return object?.sha;
}

export async function publishVersion(api, metadata, root, assertFresh) {
  const identity = parseVersion(metadata.version);
  if (metadata.schema !== 2 || identity.prerelease !== metadata.prerelease || identity.type !== metadata.type
      || !new RegExp(policy.sha_pattern).test(metadata.source_sha)) throw Error('Invalid version metadata');
  const version = identity.version;
  const releaseName = version;
  const metadataBytes = fs.readFileSync(`${root}/release.json`);
  if (canonical(JSON.parse(metadataBytes)) !== canonical(metadata)) throw Error('Release manifest changed');
  const marker = `<!-- semver-release:${version}:${sha256(metadataBytes)} -->`;
  const body = fs.readFileSync(`${root}/notes.md`, 'utf8') + `\n${marker}\n`;
  const payloads = metadata.assets;
  if (new Set(payloads.map(asset => asset.name)).size !== payloads.length) throw Error('Duplicate public asset names');
  const contentType = asset => policy.asset_content_types[path.extname(asset.path)] || 'application/octet-stream';
  for (const asset of payloads) {
    relative(asset.path);
    if (!isExecutable(fs.readFileSync(path.join(root, asset.path))) || asset.name !== `${version}-${path.basename(asset.path)}`
        || !/^[a-f0-9]{64}$/.test(asset.sha256)
        || sha256(fs.readFileSync(path.join(root, asset.path))) !== asset.sha256) throw Error('Release asset changed after assembly');
  }
  async function assetMatches(actual, expected) {
    if (!actual || actual.size !== fs.statSync(`${root}/${expected.path}`).size || actual.content_type !== contentType(expected)) return false;
    if (actual.digest) return actual.digest === `sha256:${expected.sha256}`;
    const bytes = await api.request(`/releases/assets/${actual.id}`, { binary: true, headers: { Accept: 'application/octet-stream' } });
    return sha256(bytes) === expected.sha256;
  }
  async function checkAssets(assets, complete) {
    if ((complete && assets.length !== payloads.length) || new Set(assets.map(asset => asset.name)).size !== assets.length) return false;
    for (const actual of assets) {
      const expected = payloads.find(asset => asset.name === actual.name);
      if (!expected || !await assetMatches(actual, expected)) return false;
    }
    return true;
  }
  const matchesIdentity = release => release.tag_name === version && release.name === releaseName
    && release.prerelease === identity.prerelease && release.body === body;
  let release = await api.request(`/releases/tags/${version}`, { missing: true });
  const originalRef = await api.request(`/git/ref/tags/${version}`, { missing: true });

  let assets = release ? await api.pages(`/releases/${release.id}/assets`) : [];
  if (release && !release.draft && matchesIdentity(release) && originalRef
      && await tagCommit(api, originalRef) === metadata.source_sha && await checkAssets(assets, true)) {
    await assertFresh();
    if (!release.discussion_url) await api.json('PATCH', `/releases/${release.id}`, { discussion_category_name: 'Announcements' });
    console.log(`${version} already contains identical verified content; no changes`);
    return;
  }
  let created = false;
  try {
    await assertFresh();
    if (!release) {
      release = await api.json('POST', '/releases', { tag_name: version, target_commitish: metadata.source_sha,
        name: releaseName, body, draft: true, prerelease: identity.prerelease });
      created = true;
    }
    if (!created) {
      await api.json('PATCH', `/releases/${release.id}`, { name: releaseName, body, prerelease: identity.prerelease });
      for (const actual of assets) {
        const expected = payloads.find(asset => asset.name === actual.name);
        if (!expected || !await assetMatches(actual, expected)) {
          await api.request(`/releases/assets/${actual.id}`, { method: 'DELETE' });
        }
      }
      assets = await api.pages(`/releases/${release.id}/assets`);
    }
    for (const asset of payloads) {
      if (assets.some(actual => actual.name === asset.name)) continue;
      const uploaded = await api.request(`${release.upload_url.replace(/\{.*$/, '')}?name=${encodeURIComponent(asset.name)}`, {
        method: 'POST', body: fs.readFileSync(`${root}/${asset.path}`), headers: { 'Content-Type': contentType(asset) },
      });
      if (!await assetMatches(uploaded, asset)) throw Error(`Uploaded asset verification failed: ${asset.name}`);
    }
    await assertFresh();
    const ref = await api.request(`/git/ref/tags/${version}`, { missing: true });
    if (ref && await tagCommit(api, ref) !== metadata.source_sha) {
      await api.json('PATCH', `/git/refs/tags/${version}`, { sha: metadata.source_sha, force: true });
    }
    // Only the explicitly selected version tag may be created or replaced.
    if (!ref) await api.json('POST', '/git/refs', { ref: `refs/tags/${version}`, sha: metadata.source_sha });
    assets = await api.pages(`/releases/${release.id}/assets`);
    if (!await checkAssets(assets, true)) throw Error('Draft release assets differ from the prepared version');
    await api.json('PATCH', `/releases/${release.id}`, { draft: false, discussion_category_name: 'Announcements', make_latest: identity.prerelease ? 'false' : 'legacy' });
    const published = await api.request(`/releases/${release.id}`);
    const publishedRef = await api.request(`/git/ref/tags/${version}`);
    const publishedAssets = await api.pages(`/releases/${release.id}/assets`);
    if (published.draft || !matchesIdentity(published) || await tagCommit(api, publishedRef) !== metadata.source_sha
        || !await checkAssets(publishedAssets, true)) throw Error('Published version verification failed');
  } catch (failure) {
    // Remove only a draft created by this attempt, after confirming it is still
    // our unpublished draft. Published versions and all tags are left intact.
    if (created && release) {
      try {
        const current = await api.request(`/releases/${release.id}`, { missing: true });
        if (current?.draft && matchesIdentity(current)) await api.request(`/releases/${release.id}`, { method: 'DELETE' });
      } catch (cleanup) { throw Error(`${failure.message}; draft cleanup failed: ${cleanup.message}`); }
    }
    throw failure;
  }
  console.log(`Published ${identity.type} ${version} at ${metadata.source_sha}`);
}

export async function publish(version) {
  authorizePublication();
  parseVersion(version);
  if (!process.env.GH_TOKEN) throw Error('Missing automatic workflow token');
  const repo = process.env.GITHUB_REPOSITORY;
  const api = client(process.env.GH_TOKEN, repo);
  await protect(repo, api);
  const root = `build/releases/${version}`;
  const metadata = JSON.parse(fs.readFileSync(`${root}/release.json`));
  const publication = JSON.parse(fs.readFileSync(`${root}/publication.json`));
  if (metadata.version !== version || publication.version !== version || metadata.source_sha !== publication.source_sha
      || publication.controller_sha !== process.env.GITHUB_SHA) throw Error('Release controller/source mismatch');
  if (canonical(metadata.targets) !== canonical(publication.targets.map(({ contract, ...target }) => target))) {
    throw Error('Public build identities differ from accepted validation');
  }
  for (const target of publication.targets) {
    const { verifyDistribution } = await import('./core.mjs');
    if (!target.contract?.accepted || target.contract.source_sha !== metadata.source_sha) throw Error('Release requires accepted admin validation');
    const { restore } = await import('../receipts/github.mjs');
    const acceptedRoot = `build/tmp/receipts/publication/${version}/${target.name}`;
    await restore(target.contract, acceptedRoot);
    const expected = verifyDistribution(acceptedRoot, target.contract);
    const packaged = verifyDistribution(`${root}/packages/${target.name}`, target.contract);
    const publicTarget = metadata.targets.find(entry => entry.name === target.name);
    if (!publicTarget || canonical(publicTarget.manifest) !== canonical(packaged.manifest)
        || canonical(expected.manifest) !== canonical(packaged.manifest)) throw Error('Published packages differ from accepted validation');
  }
  const expectedAssets = [];
  for (const target of publication.targets) {
    for (const item of metadata.targets.find(entry => entry.name === target.name).manifest) {
      const bytes = fs.readFileSync(`${root}/packages/${target.name}/${item.path}`);
      if (!isExecutable(bytes)) continue;
      const file = `executables/${target.name}-${item.path.replaceAll('/', '-')}`;
      expectedAssets.push({ path: file, name: `${version}-${path.basename(file)}`, sha256: sha256(bytes) });
    }
  }
  if (canonical(expectedAssets) !== canonical(metadata.assets)) throw Error('Executable assets differ from accepted builds');
  if (metadata.targets.length !== publication.targets.length) throw Error('Public target coverage differs from accepted validation');
  const assertFresh = async () => {
    const ref = await api.request('/git/ref/heads/source');
    if (ref.object.sha !== publication.controller_sha) throw Error('Stale release run: source advanced');
    const contract = await api.request(`/contents/ci/releases/versions.toml?ref=${ref.object.sha}`);
    if (sha256(Buffer.from(contract.content, 'base64')) !== publication.contract_hash) throw Error('Release selection changed after assembly');
    await protect(repo, api);
  };
  await publishVersion(api, metadata, root, assertFresh);
}
