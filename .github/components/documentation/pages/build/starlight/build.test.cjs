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
  assert.ok(layout.includes('--docs-article-width: 883px;'));
  assert.ok(layout.includes('--sl-sidebar-width: 18rem;'));
  assert.ok(!layout.includes('--sl-color-bg:'));
  assert.ok(!projectTheme.includes('--sl-color-accent:'));
  assert.ok(astro.includes('ThemeSelect.astro'));
  assert.ok(astro.includes('ThemeProvider.astro'));
  assert.ok(astro.includes("themes: ['github-dark']"));
  assert.ok(astro.includes('useStarlightDarkModeSwitch: false'));
  assert.ok(!astro.includes('localStorage'));
  assert.ok(!collection.includes('content/i18n'));
});

test('Measured dark palette, independent presentation layers and forced colors', () => {
  const astro = fs.readFileSync(path.join(__dirname, 'astro.config.mjs'), 'utf8');
  const entries = [...astro.matchAll(/['"](\.\/src\/styles\/[^'"]+\.css)['"]/g)].map(match => match[1]);
  assert.deepEqual(entries, [
    './src/styles/theme/fallback.css',
    './src/styles/layout.css',
    './src/styles/typography.css',
    './src/styles/navigation.css',
    './src/styles/reference.css',
    './src/styles/project.css',
    './src/styles/theme/forced-colors.css',
  ]);
  const fallback = fs.readFileSync(path.join(__dirname, 'src/styles/theme/fallback.css'), 'utf8');
  const forced = fs.readFileSync(path.join(__dirname, 'src/styles/theme/forced-colors.css'), 'utf8');
  assert.match(fallback, /--docs-surface: #121215;/);
  assert.match(fallback, /--docs-link: #528bff;/);
  assert.match(fallback, /color-scheme: dark;/);
  assert.doesNotMatch(fallback, /data-theme=['"]light|color-scheme: light/);
  assert.match(forced, /@media \(forced-colors: active\)/);
  assert.match(forced, /--docs-selected: Highlight;/);
  const tokens = css => [...new Set([...css.matchAll(/(--(?:docs|sl-color)-[a-z0-9-]+):/g)].map(match => match[1]))].sort();
  assert.deepEqual(tokens(forced), tokens(fallback));
  const provider = fs.readFileSync(path.join(__dirname, 'src/components/ThemeProvider.astro'), 'utf8');
  assert.match(provider, /dataset.theme = 'dark'/);
  const example = fs.readFileSync(path.join(root, 'content/docs/reference-example.mdx'), 'utf8');
  assert.match(example, /<ApiSummary .*members=/);
  assert.match(example, /\x60\x60\x60luau/);
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

 test('API reference components use project type metadata and registered member anchors', () => {
  const example = fs.readFileSync(path.join(root,'content/docs/reference-example.mdx'),'utf8');
  const ids = [...example.matchAll(/<ApiMember [^>]*id="([^"]+)"/g)].map(m=>m[1]);
  const summary = [...example.matchAll(/"href":"#([^"]+)"/g)].map(m=>m[1]);
  assert.equal(ids.length,13);
  assert.deepEqual(summary.sort(),ids.sort());
  for(const id of ids) assert.ok(example.includes('### '+id+'\n'));
  const signature=fs.readFileSync(path.join(__dirname,'src/components/ApiSignature.astro'),'utf8');
  assert.match(signature,/import builtins/);
  assert.doesNotMatch(signature,/Lorem ipsum/);
  assert.match(signature,/<a class="api-type"/);
  assert.match(signature,/<button type="button" class="api-type"/);
});

test('API icon families share captured geometry and exact colors without inventing constructors', () => {
  const icons = require('./src/data/api-icons.json');
  assert.deepEqual(Object.keys(icons).sort(), ['event','method','property']);
  assert.deepEqual([icons.property.color,icons.method.color,icons.event.color], ['#1AC8FF','#E26CF4','#F2BA2A']);
  assert.deepEqual([icons.property.paths.length,icons.method.paths.length,icons.event.paths.length],[1,6,1]);
  const component = fs.readFileSync(path.join(__dirname,'src/components/ApiIcon.astro'),'utf8');
  assert.match(component,/callback: 'method'/);
  assert.match(component,/signal: 'event'/);
  assert.match(component,/icon && <svg/);
});

test('multiline callable signatures preserve nested parentheses and return tuples', async () => {
  const {formatSignature}=await import('./src/data/format-signature.mjs');
  assert.deepEqual(formatSignature('Get(key: string, fn: (x: number) -> boolean): (unknown, boolean)'),{before:'Get (',args:'key: string, fn: (x: number) -> boolean',after:'): (unknown, boolean)'});
  assert.equal(formatSignature('Value: string'),null);
  assert.equal(formatSignature('OnInvoke: (x: number) -> boolean'),null);
  assert.equal(formatSignature('new()'),null);
});
