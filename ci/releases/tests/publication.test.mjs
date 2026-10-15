import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import test from 'node:test';
import assert from 'node:assert/strict';
import { parseVersion, sha256, write } from '../core.mjs';
import { finalizeAssets, isExecutable } from '../render.mjs';
import { publishVersion } from '../publish.mjs';

const source = 'a'.repeat(40);
function fixture(t, options = {}) {
  const root = fs.mkdtempSync(path.join(os.tmpdir(), 'semver-publication-'));
  t.after(() => fs.rmSync(root, { recursive: true, force: true }));
  const releases = new Map(), refs = new Map(), assetData = new Map(), writes = [];
  let sequence = 1, failedAfterPublish = false;
  const find = id => [...releases.values()].find(release => release.id === Number(id));
  const api = {
    async pages(route) { return structuredClone(find(route.split('/')[2]).assets); },
    async request(route, request = {}) {
      if (route.startsWith('https://uploads.github.com/')) {
        writes.push(['UPLOAD', route]);
        if (options.failUpload) throw Error('upload failed');
        const url = new URL(route), release = find(url.pathname.split('/').at(-1));
        const data = Buffer.from(request.body), id = sequence++;
        const asset = { id, name: url.searchParams.get('name'), size: data.length,
          digest: options.noDigest ? null : `sha256:${sha256(data)}`, content_type: request.headers['Content-Type'] };
        assetData.set(id, data); release.assets.push(asset);
        if (options.badDigest) asset.digest = 'sha256:' + 'f'.repeat(64);
        return structuredClone(asset);
      }
      if (route.startsWith('/git/ref/tags/')) return structuredClone(refs.get(route.slice('/git/ref/tags/'.length)) || null);
      if (route.startsWith('/git/tags/')) return { object: { type: 'commit', sha: source } };
      if (route.startsWith('/releases/assets/')) {
        const id = Number(route.split('/').at(-1));
        if (request.method === 'DELETE') {
          writes.push(['DELETE', route]);
          for (const release of releases.values()) release.assets = release.assets.filter(asset => asset.id !== id);
          return null;
        }
        return assetData.get(id);
      }
      const release = route.startsWith('/releases/tags/') ? releases.get(route.slice('/releases/tags/'.length)) : find(route.split('/').at(-1));
      if (request.method === 'DELETE') {
        assert.ok(release.draft, 'published releases must never be deleted');
        writes.push(['DELETE', route]); releases.delete(release.tag_name); return null;
      }
      if (release && !release.draft && options.failVerification && !failedAfterPublish) {
        failedAfterPublish = true;
        return { ...structuredClone(release), body: 'simulated verification mismatch' };
      }
      return structuredClone(release || null);
    },
    async json(method, route, value) {
      writes.push([method, route]);
      if (route === '/releases' && method === 'POST') {
        assert.ok(!releases.has(value.tag_name));
        const release = { id: sequence++, ...value, assets: [] };
        release.upload_url = `https://uploads.github.com/releases/${release.id}{?name}`;
        releases.set(value.tag_name, release);
        if (options.autoTag) refs.set(value.tag_name, { object: { type: 'commit', sha: value.target_commitish } });
        return structuredClone(release);
      }
      if (route.startsWith('/git/refs')) {
        if (method === 'PATCH') { const name = route.slice('/git/refs/tags/'.length); refs.set(name, { object: { type: 'commit', sha: value.sha } }); return refs.get(name); }
        const name = value.ref.slice('refs/tags/'.length);
        assert.ok(!refs.has(name));
        const ref = { object: { type: 'commit', sha: value.sha } }; refs.set(name, ref); return structuredClone(ref);
      }
      assert.ok(route.startsWith('/releases/') && method === 'PATCH', 'unexpected mutation');
      const release = find(route.split('/').at(-1));

      if (options.failPromotion) throw Error('promotion failed');
      Object.assign(release, value);
      if (value.discussion_category_name) release.discussion_url = 'https://github.com/example/project/discussions/1';
      if (options.lostPromotionResponse) { options.lostPromotionResponse = false; throw Error('response lost after promotion'); }
      return structuredClone(release);
    },
  };
  function prepare(version = '1.2.0', content = 'packages') {
    const dir = path.join(root, version);
    write(`${dir}/app`, '#!/bin/sh\n' + content);
    write(`${dir}/notes.md`, `Notes for ${version}`);
    write(`${dir}/graph.png`, 'image');
    const metadata = finalizeAssets(dir, { schema: 2, ...parseVersion(version), source_sha: source, from: 'beginning', targets: [] },
      ['app']);
    return { metadata, dir };
  }
  const publish = (prepared, fresh = async () => {}) => publishVersion(api, prepared.metadata, prepared.dir, fresh);
  return { api, releases, refs, writes, prepare, publish };
}

test('stable and prerelease publication use exact SemVer tags and correct GitHub types', async t => {
  const f = fixture(t);
  for (const version of ['1.2.0', '1.3.0-pre.1']) {
    await f.publish(f.prepare(version));
    const release = f.releases.get(version);
    assert.equal(release.draft, false);
    assert.equal(release.prerelease, version.includes('-pre.'));
    assert.equal(release.name, `${version.includes('-pre.') ? 'Pre-Release' : 'Release'} ${version}`);
    assert.equal(f.refs.get(version).object.sha, source);
    assert.deepEqual(release.assets.map(asset => asset.name), [`${version}-app`]);
    assert.ok(release.discussion_url);
  }
  assert.ok(f.writes.filter(([method, route]) => route.startsWith('/git/')).every(([method]) => method === 'POST'));
});

test('identical repeated publication is a strict no-op, including after internal restaging', async t => {
  const f = fixture(t), prepared = f.prepare();
  await f.publish(prepared);
  const before = structuredClone([...f.releases]), mutations = f.writes.length;
  write(`${prepared.dir}/publication.json`, { controller_sha: 'different', staging_release_id: 999 });
  await f.publish(prepared);
  assert.equal(f.writes.length, mutations);
  assert.deepEqual([...f.releases], before);
});

test('prerelease promotion creates another release and leaves the prerelease unchanged', async t => {
  const f = fixture(t), pre = f.prepare('1.3.0-pre.1');
  await f.publish(pre);
  const previous = structuredClone(f.releases.get('1.3.0-pre.1'));
  await f.publish(f.prepare('1.3.0'));
  assert.deepEqual(f.releases.get('1.3.0-pre.1'), previous);
  assert.equal(f.releases.size, 2);
  assert.equal(f.refs.size, 2);
});

test('changed content replaces the selected version and a conflicting source tag', async t => {
  const f = fixture(t);
  await f.publish(f.prepare());
  const id = f.releases.get('1.2.0').id;
  f.refs.set('1.2.0', { object: { type: 'commit', sha: 'b'.repeat(40) } });
  const changed = f.prepare('1.2.0', 'new executable');
  await f.publish(changed);
  assert.equal(f.releases.get('1.2.0').id, id);
  assert.equal(f.refs.get('1.2.0').object.sha, source);
  assert.equal(f.releases.get('1.2.0').assets.length, 1);
});

test('a matching existing annotated version tag is reused without rewriting it', async t => {
  const f = fixture(t), prepared = f.prepare();
  f.refs.set('1.2.0', { object: { type: 'tag', sha: 'c'.repeat(40) } });
  await f.publish(prepared);
  assert.equal(f.refs.get('1.2.0').object.sha, 'c'.repeat(40));
  assert.ok(!f.writes.some(([, route]) => route.startsWith('/git/')));
});

test('historical releases and tags are left unchanged', async t => {
  const f = fixture(t), history = { id: 999, tag_name: 'historical', draft: false, body: 'legacy content', assets: [] };
  f.releases.set('historical', history); f.refs.set('historical', { object: { sha: 'b'.repeat(40) } });
  const previous = structuredClone(history);
  await f.publish(f.prepare());
  assert.deepEqual(f.releases.get('historical'), previous);
  assert.equal(f.refs.get('historical').object.sha, 'b'.repeat(40));
});

test('missing GitHub asset digests are verified by downloading bytes', async t => {
  const f = fixture(t, { noDigest: true }), prepared = f.prepare();
  await f.publish(prepared);
  const mutations = f.writes.length;
  await f.publish(prepared);
  assert.equal(f.writes.length, mutations);
});

for (const failure of ['failUpload', 'badDigest', 'failPromotion']) test(`${failure} cleans only the new unpublished draft`, async t => {
  const f = fixture(t, { [failure]: true, autoTag: true });
  f.refs.set('historical', { object: { sha: 'b'.repeat(40) } });
  await assert.rejects(() => f.publish(f.prepare()));
  assert.equal(f.releases.size, 0);
  assert.equal(f.refs.get('historical').object.sha, 'b'.repeat(40));
  assert.equal(f.refs.get('1.2.0').object.sha, source, 'even a newly created tag is not deleted');
});

test('a lost promotion response never rolls back a published version and retry is a no-op', async t => {
  const f = fixture(t, { lostPromotionResponse: true }), prepared = f.prepare();
  await assert.rejects(() => f.publish(prepared), /response lost/);
  assert.equal(f.releases.get('1.2.0').draft, false);
  const mutations = f.writes.length;
  await f.publish(prepared);
  assert.equal(f.writes.length, mutations);
});

test('post-publication verification failure preserves the published version', async t => {
  const f = fixture(t, { failVerification: true }), prepared = f.prepare();
  await assert.rejects(() => f.publish(prepared), /verification failed/);
  assert.equal(f.releases.get('1.2.0').draft, false);
  assert.equal(f.refs.get('1.2.0').object.sha, source);
});

test('stale source before publication makes no mutations', async t => {
  const f = fixture(t);
  await assert.rejects(() => f.publish(f.prepare(), async () => { throw Error('source advanced'); }), /source advanced/);
  assert.equal(f.writes.length, 0);
});

test('source-only replacement removes all uploaded attachments', async t => {
  const f = fixture(t), prepared = f.prepare();
  await f.publish(prepared);
  prepared.metadata = finalizeAssets(prepared.dir, prepared.metadata, []);
  await f.publish(prepared);
  assert.deepEqual(f.releases.get('1.2.0').assets, []);
});

test('a matching publisher-owned draft can resume without replacement', async t => {
  const f = fixture(t), prepared = f.prepare();
  const marker = `<!-- semver-release:1.2.0:${sha256(fs.readFileSync(`${prepared.dir}/release.json`))} -->`;
  const existing = await f.api.json('POST', '/releases', { tag_name: '1.2.0', target_commitish: source,
    name: 'Release 1.2.0', body: fs.readFileSync(`${prepared.dir}/notes.md`, 'utf8') + `\n${marker}\n`, draft: true, prerelease: false });
  await f.publish(prepared);
  assert.equal(f.releases.get('1.2.0').id, existing.id);
  assert.equal(f.releases.get('1.2.0').draft, false);
  assert.equal(f.writes.filter(([method, route]) => method === 'POST' && route === '/releases').length, 1);
});

test('source advancing during upload prevents publication and preserves tags', async t => {
  const f = fixture(t, { autoTag: true });
  let checks = 0;
  await assert.rejects(() => f.publish(f.prepare(), async () => {
    if (++checks > 1) throw Error('source advanced');
  }), /source advanced/);
  assert.equal(f.releases.size, 0);
  assert.equal(f.refs.get('1.2.0').object.sha, source);
});

test('changed local assets are rejected before any remote mutation', async t => {
  const f = fixture(t), prepared = f.prepare();
  fs.writeFileSync(`${prepared.dir}/app`, 'tampered');
  await assert.rejects(() => f.publish(prepared), /asset changed/);
  assert.equal(f.writes.length, 0);
});

 test('executable selection excludes metadata, libraries and fake executable extensions', () => {
  for (const value of ['{}', 'report', 'MZfake.exe', 'archive']) assert.equal(isExecutable(Buffer.from(value)), false);
  assert.equal(isExecutable(Buffer.from('#!/bin/sh\necho hi')), true);
  const pe = Buffer.alloc(128); pe.write('MZ'); pe.writeUInt32LE(64,60); pe.writeUInt32LE(0x4550,64);
  assert.equal(isExecutable(pe), true);
  pe.writeUInt16LE(0x2000,86); assert.equal(isExecutable(pe), false);
  const elf = Buffer.alloc(128); Buffer.from([0x7f,0x45,0x4c,0x46,2,1]).copy(elf); elf.writeUInt16LE(2,16);
  assert.equal(isExecutable(elf), true);
  elf.writeUInt16LE(3,16); assert.equal(isExecutable(elf), false);
  elf.writeBigUInt64LE(64n,32); elf.writeUInt16LE(56,54); elf.writeUInt16LE(1,56); elf.writeUInt32LE(3,64);
  assert.equal(isExecutable(elf), true);
});
