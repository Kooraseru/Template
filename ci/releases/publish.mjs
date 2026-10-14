import fs from 'node:fs';
import path from 'node:path';
import { sha256, canonical, write, policy, protectionsValid } from './core.mjs';

export function client(token, repository, fetcher = fetch) {
  const base = `https://api.github.com/repos/${repository}`;
  async function request(route, options = {}) {
    const url = route.startsWith('https://') ? route : base + route;
    if (!/^https:\/\/(api|uploads)\.github\.com\//.test(url)) throw Error('Unexpected GitHub API host');
    for (let attempt = 0; attempt < policy.retry_attempts; attempt++) {
      const response = await fetcher(url, { ...options, headers: {
        Accept: 'application/vnd.github+json', Authorization: `Bearer ${token}`,
        'X-GitHub-Api-Version': '2022-11-28', ...(options.headers || {}),
      } });
      if (response.status === 404 && options.missing) return null;
      if (!response.ok) {
        if (response.status >= 500 && ['GET', 'PATCH', 'DELETE'].includes(options.method || 'GET') && attempt + 1 < policy.retry_attempts) {
          await new Promise(resolve => setTimeout(resolve, 1000 * (attempt + 1))); continue;
        }
        throw Error(`GitHub ${options.method || 'GET'} ${route}: ${response.status} ${await response.text()}`);
      }
      return response.status === 204 ? null : response.json();
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
  const rulesets = await Promise.all(summaries.map(set => api.request(`/rulesets/${set.id}`)));
  if (!protectionsValid(rulesets)) throw Error('Official publication requires source PR/check protections and admin-only PR merging. See ci/releases/README.md.');
  return true;
}
export async function updateChannel(api, metadata, root, assertFresh) {
  const channel = metadata.channel;
  const oldRelease = await api.request(`/releases/tags/${channel}`, { missing: true });
  const oldRef = await api.request(`/git/ref/tags/${channel}`, { missing: true });
  const generation = sha256(canonical({ source: metadata.source_sha, selection: metadata.selection_hash,
    targets: metadata.targets, assets: metadata.assets })).slice(0, 16);
  const marker = `<!-- release-generation:${generation} -->`;
  if (oldRelease?.body?.includes(marker) && oldRef?.object?.sha === metadata.source_sha) {
    console.log(`${channel} already matches verified generation ${generation}`); return;
  }
  let release = oldRelease, created = false, moved = false;
  const uploaded = [];
  const assetNames = new Set();
  try {
    await assertFresh();
    if (!release) {
      release = await api.json('POST', '/releases', { tag_name: channel, target_commitish: metadata.source_sha,
        name: channel, draft: true, prerelease: metadata.prerelease });
      created = true;
    }
    const payloads = [...metadata.assets, { path: 'release.json', name: `${channel}-${metadata.source_sha}-release.json`, sha256: sha256(fs.readFileSync(`${root}/release.json`)) }];
    const existing = await api.pages(`/releases/${release.id}/assets`);
    for (const asset of payloads) {
      // A generation suffix prevents overwriting previous assets while staging replacements for the same SHA.
      const name = asset.name.replace(`${channel}-${metadata.source_sha}-`, `${channel}-${metadata.source_sha}-${generation}-`);
      assetNames.add(name);
      const data = fs.readFileSync(path.join(root, asset.path));
      if (sha256(data) !== asset.sha256) throw Error(`Release asset changed after assembly: ${asset.path}`);
      let candidate = existing.find(entry => entry.name === name);
      if (candidate && candidate.digest !== `sha256:${asset.sha256}`) {
        // Unverified leftovers from a failed staging attempt cannot be reused.
        await api.request(`/releases/assets/${candidate.id}`, { method: 'DELETE' }); candidate = null;
      }
      if (!candidate) {
        candidate = await api.request(`${release.upload_url.replace(/\{.*$/, '')}?name=${encodeURIComponent(name)}`, {
          method: 'POST', body: data, headers: { 'Content-Type': 'application/octet-stream' },
        });
        uploaded.push(candidate.id);
      }
      if (candidate.digest !== `sha256:${asset.sha256}` || candidate.size !== data.length) throw Error(`Uploaded asset verification failed: ${name}`);
    }
    await assertFresh();
    const currentRef = await api.request(`/git/ref/tags/${channel}`, { missing: true });
    if ((currentRef?.object?.sha || null) !== (oldRef?.object?.sha || null)
        && !(created && !oldRef && currentRef?.object?.sha === metadata.source_sha)) throw Error('Channel tag changed during publication');
    if (currentRef) await api.json('PATCH', `/git/refs/tags/${channel}`, { sha: metadata.source_sha, force: true });
    else await api.json('POST', '/git/refs', { ref: `refs/tags/${channel}`, sha: metadata.source_sha });
    moved = true;
    const body = fs.readFileSync(`${root}/notes.md`, 'utf8').replaceAll(`${channel}-${metadata.source_sha}-`, `${channel}-${metadata.source_sha}-${generation}-`) + `\n${marker}\n`;
    await api.json('PATCH', `/releases/${release.id}`, { tag_name: channel, name: channel, body,
      draft: false, prerelease: metadata.prerelease, make_latest: channel === 'stable' ? 'true' : 'false' });
    const verifiedRef = await api.request(`/git/ref/tags/${channel}`);
    const verifiedRelease = await api.request(`/releases/${release.id}`);
    if (verifiedRef.object.sha !== metadata.source_sha || !verifiedRelease.body?.includes(marker)) throw Error('Published channel verification failed');
  } catch (failure) {
    const recoveryFailures = [];
    const recover = async operation => { try { await operation(); } catch (error) { recoveryFailures.push(error.message); } };
    if (moved) await recover(() => oldRef
      ? api.json('PATCH', `/git/refs/tags/${channel}`, { sha: oldRef.object.sha, force: true })
      : api.request(`/git/refs/tags/${channel}`, { method: 'DELETE' }));
    if (created && release) {
      await recover(() => api.request(`/releases/${release.id}`, { method: 'DELETE' }));
      if (!oldRef && !moved) await recover(async () => {
        const ref = await api.request(`/git/ref/tags/${channel}`, { missing: true });
        if (ref?.object?.sha === metadata.source_sha) await api.request(`/git/refs/tags/${channel}`, { method: 'DELETE' });
      });
    }
    else if (release) {
      await recover(() => api.json('PATCH', `/releases/${release.id}`, {
        body: oldRelease.body, name: oldRelease.name, draft: oldRelease.draft, prerelease: oldRelease.prerelease,
      }));
      for (const id of uploaded) await recover(() => api.request(`/releases/assets/${id}`, { method: 'DELETE' }));
    }
    throw Error(`${failure.message}${recoveryFailures.length ? `; RECOVERY INCOMPLETE: ${recoveryFailures.join('; ')}` : '; previous channel restored'}`);
  }
  // Publication is verified. Cleanup failure must not roll back a valid new channel.
  for (const asset of await api.pages(`/releases/${release.id}/assets`)) {
    if (!assetNames.has(asset.name) && new RegExp(`^${channel}-[a-f0-9]{40}-[a-f0-9]{16}-`).test(asset.name)) {
      try { await api.request(`/releases/assets/${asset.id}`, { method: 'DELETE' }); }
      catch (error) { console.warn(`Published successfully; old asset cleanup failed: ${error.message}`); }
    }
  }
  console.log(`Published ${channel} at ${metadata.source_sha}`);
}
export async function publish(channel) {
  if (process.env.ACT === 'true' || process.env.GITHUB_ACTIONS !== 'true'
      || process.env.GITHUB_EVENT_NAME !== 'push' || process.env.GITHUB_REF !== 'refs/heads/source') throw Error('Local or untrusted publication denied');
  if (!policy.channels.includes(channel) || !process.env.GH_TOKEN) throw Error('Missing channel or automatic workflow token');
  const repo = process.env.GITHUB_REPOSITORY;
  const api = client(process.env.GH_TOKEN, repo);
  await protect(repo, api);
  const directory = `build/releases/${channel}`;
  const commits = fs.readdirSync(directory).filter(name => new RegExp(policy.sha_pattern).test(name));
  if (commits.length !== 1) throw Error('Expected exactly one prepared source SHA for this channel');
  const root = `${directory}/${commits[0]}`;
  const metadata = JSON.parse(fs.readFileSync(`${root}/release.json`));
  if (metadata.channel !== channel || metadata.source_sha !== commits[0] || metadata.controller_sha !== process.env.GITHUB_SHA) throw Error('Release controller/source mismatch');
  for (const target of metadata.targets) {
    const { verifyDistribution } = await import('./core.mjs');
    verifyDistribution(`${root}/packages/${target.name}`, { name: target.name, source_sha: metadata.source_sha, fingerprint: target.fingerprint });
  }
  const assertFresh = async () => {
    const ref = await api.request('/git/ref/heads/source');
    if (ref.object.sha !== metadata.controller_sha || (metadata.latest && ref.object.sha !== metadata.source_sha)) throw Error('Stale release run: source advanced; retaining the published channel');
    const contract = await api.request(`/contents/ci/releases/channels.toml?ref=${ref.object.sha}`);
    if (sha256(Buffer.from(contract.content, 'base64')) !== metadata.contract_hash) throw Error('Release contract changed after assembly');
    await protect(repo, api);
  };
  try { await assertFresh(); } catch (error) {
    if (error.message.startsWith('Stale release run:')) { console.log(error.message); return; }
    throw error;
  }
  await updateChannel(api, metadata, root, assertFresh);
}
