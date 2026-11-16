'use strict';
const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const os = require('node:os');
const { copyAssets, root } = require('./build.cjs');

test('Starlight site is configured as a component, not another workflow', () => {
  const site = __dirname;
  const manifest = require('./package.json');
  assert.equal(manifest.private, true);
  assert.ok(manifest.dependencies['@astrojs/starlight']);
  assert.ok(manifest.dependencies.astro);
  const astro = fs.readFileSync(path.join(site, 'astro.config.mjs'), 'utf8');
  const collection = fs.readFileSync(path.join(site, 'src/content.config.mjs'), 'utf8');
  assert.ok(astro.includes("resolve(here, 'dist')"));
  assert.ok(fs.readFileSync(path.join(site, 'build.cjs'), 'utf8').includes('build/github/pages'));
  assert.ok(astro.includes('starlight({'));
  assert.ok(!astro.includes('sidebar: ['));
  assert.ok(collection.includes('content/docs'));
  assert.ok(collection.includes('!repository/**'));
  assert.ok(!collection.includes('content/i18n'));
});

test('Static image copier preserves nested paths', t => {
  const tmp = fs.mkdtempSync(path.join(os.tmpdir(), 'starlight-assets-'));
  t.after(() => fs.rmSync(tmp, { recursive: true, force: true }));
  const from = path.join(tmp, 'from'), to = path.join(tmp, 'to');
  fs.mkdirSync(path.join(from, 'nested'), { recursive: true });
  fs.writeFileSync(path.join(from, 'nested/logo.svg'), 'image');
  copyAssets(from, to);
  assert.equal(fs.readFileSync(path.join(to, 'nested/logo.svg'), 'utf8'), 'image');
  assert.ok(fs.existsSync(path.join(root, 'content/docs/index.md')));
});
