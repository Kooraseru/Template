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
  assert.doesNotMatch(collection.replace(/^\s*\/\/.*$/gm, ''), /\bglob\s*\(/);
  assert.ok(astro.includes('./src/styles/project.css'));
  assert.ok(astro.includes("favicon: '/images/favicon.png'"));
  const authoredFavicon = path.join(root, 'content/images/favicon.png');
  assert.ok(fs.existsSync(authoredFavicon));
  const signature = fs.readFileSync(authoredFavicon).subarray(0, 8).toString('hex');
  assert.equal(signature, '89504e470d0a1a0a');
  assert.ok(fs.existsSync(path.join(root, 'content/theme.css')));
  const layout = fs.readFileSync(path.join(site, 'src/styles/layout.css'), 'utf8');
  const projectTheme = fs.readFileSync(path.join(root, 'content/theme.css'), 'utf8');
  assert.ok(layout.includes('--sl-content-width: 52rem;'));
  assert.ok(layout.includes('--sl-sidebar-width: 17rem;'));
  assert.ok(!layout.includes('--sl-color-bg:'));
  assert.ok(!projectTheme.includes('--sl-color-accent:'));
  assert.ok(!astro.includes('ThemeSelect.astro'));
  assert.ok(!astro.includes('localStorage'));
  assert.ok(!collection.includes('content/i18n'));
});

test('Theme stylesheets are ordered baseline, native, project and accessibility', () => {
  const astro = fs.readFileSync(path.join(__dirname, 'astro.config.mjs'), 'utf8');
  const entries = [...astro.matchAll(/['"](\.\/src\/styles\/[^'"]+\.css)['"]/g)].map(match => match[1]);
  assert.deepEqual(entries, [
    './src/styles/layout.css',
    './src/styles/theme/fallback.css',
    './src/styles/theme/native.css',
    './src/styles/project.css',
    './src/styles/theme/forced-colors.css',
  ]);
  const read = file => fs.readFileSync(path.join(__dirname, 'src/styles/theme', file), 'utf8');
  const fallback = read('fallback.css');
  const native = read('native.css');
  const forced = read('forced-colors.css');
  assert.match(fallback, /--sl-color-bg: #141821;/);
  assert.match(fallback, /--sl-color-bg: #ffffff;/);
  assert.match(fallback, /color-scheme: dark;/);
  assert.match(fallback, /color-scheme: light;/);
  assert.ok(fallback.includes("root[data-theme='light']"));
  assert.doesNotMatch(fallback, /@supports|@media/);
  assert.match(native, /@supports \(color: Canvas\)/);
  assert.match(native, /--docs-accent: AccentColor;/);
  assert.match(native, /--sl-color-bg: Canvas;/);
  assert.match(native, /color-mix\(in srgb/);
  assert.doesNotMatch(native, /#[0-9a-f]{3,8}\b|--docs-user-accent|@media/i);
  assert.match(forced, /@media \(forced-colors: active\)/);
  assert.match(forced, /--sl-color-accent: LinkText;/);
  assert.match(forced, /--sl-color-bg-accent: Highlight;/);
  assert.doesNotMatch(forced, /#[0-9a-f]{3,8}\b|color-mix\(/i);
  const tokens = css => [...new Set([...css.matchAll(/(--sl-color-[a-z0-9-]+):/g)].map(match => match[1]))].sort();
  assert.deepEqual(tokens(native), tokens(fallback));
  assert.deepEqual(tokens(forced), tokens(fallback));
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
