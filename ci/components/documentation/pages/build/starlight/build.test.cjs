'use strict';
const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const os = require('node:os');
const { copyAssets, prepareSite, stageFavicon, root } = require('./build.cjs');

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
  assert.ok(collection.includes('docsLoader()'));
  assert.ok(!collection.includes('glob('));
  assert.ok(astro.includes('./src/styles/project.css'));
  assert.ok(astro.includes("favicon: '/images/favicon.png'"));
  const authoredFavicon = path.join(root, 'content/images/favicon.png');
  assert.ok(fs.existsSync(authoredFavicon));
  const signature = fs.readFileSync(authoredFavicon).subarray(0, 8).toString('hex');
  assert.equal(signature, '89504e470d0a1a0a');
  assert.ok(fs.existsSync(path.join(root, 'content/theme.css')));
  const layout = fs.readFileSync(path.join(site, 'src/styles/layout.css'), 'utf8');
  const palette = fs.readFileSync(path.join(site, 'src/styles/palette.css'), 'utf8');
  const projectTheme = fs.readFileSync(path.join(root, 'content/theme.css'), 'utf8');
  assert.ok(astro.includes('./src/styles/palette.css'));
  // Hardcoded fallback precedes a supported system-color override.
  assert.ok(palette.includes('--sl-color-bg: #141821;'));
  assert.ok(palette.includes('--sl-color-bg: #ffffff;'));
  assert.ok(palette.includes('@supports (color: Canvas)'));
  assert.ok(palette.includes('color-mix(in srgb'));
  assert.ok(palette.includes('--sl-color-bg: Canvas;'));
  assert.ok(palette.indexOf('--sl-color-bg: #ffffff;') < palette.indexOf('--sl-color-bg: Canvas;'));
  assert.ok(palette.includes('@media (forced-colors: active)'));
  assert.ok(palette.includes("root[data-theme='light']"));
  assert.ok(layout.includes('--sl-content-width: 52rem;'));
  assert.ok(layout.includes('--sl-sidebar-width: 17rem;'));
  assert.ok(!layout.includes('--sl-color-bg:'));
  assert.ok(!projectTheme.includes('--sl-color-accent:'));
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

test('Content staging creates a flat docs root, excludes repository templates and copies the project theme', t => {
  const temporary = fs.mkdtempSync(path.join(os.tmpdir(), 'starlight-stage-'));
  t.after(() => fs.rmSync(temporary, { recursive: true, force: true }));
  const docs = path.join(temporary, 'authored'), output = path.join(temporary, 'staged');
  const theme = path.join(temporary, 'theme.css'), stylesheet = path.join(temporary, 'project.css');
  fs.mkdirSync(path.join(docs, 'guides'), { recursive: true });
  fs.mkdirSync(path.join(docs, 'repository'), { recursive: true });
  fs.writeFileSync(path.join(docs, 'index.md'), '---\ntitle: Home\n---\n');
  fs.writeFileSync(path.join(docs, 'guides', 'intro.mdx'), '---\ntitle: Intro\n---\n');
  fs.writeFileSync(path.join(docs, 'repository', 'README.md'), '# Generated README');
  fs.writeFileSync(theme, ':root { --sl-color-accent: blue; }');
  prepareSite({ docs, stagedDocs: output, theme, stagedTheme: stylesheet });
  assert.ok(fs.existsSync(path.join(output, 'index.md')));
  assert.ok(fs.existsSync(path.join(output, 'guides', 'intro.mdx')));
  assert.ok(!fs.existsSync(path.join(output, 'repository')));
  assert.match(fs.readFileSync(stylesheet, 'utf8'), /accent: blue/);
  fs.rmSync(path.join(docs, 'guides'), { recursive: true });
  prepareSite({ docs, stagedDocs: output, theme, stagedTheme: stylesheet });
  assert.ok(!fs.existsSync(path.join(output, 'guides')));
});

test('favicon is staged from authored assets and can be replaced per repository', t => {
  const temp = fs.mkdtempSync(path.join(os.tmpdir(), 'starlight-favicon-'));
  t.after(() => fs.rmSync(temp, { recursive: true, force: true }));
  const source = path.join(root, 'content/images/favicon.png');
  const destination = path.join(temp, 'public/images/favicon.png');
  stageFavicon(source, destination);
  assert.deepEqual(fs.readFileSync(destination), fs.readFileSync(source));
  assert.throws(() => stageFavicon(path.join(temp, 'missing.png'), destination),
    /Missing or invalid authored favicon/);
});
