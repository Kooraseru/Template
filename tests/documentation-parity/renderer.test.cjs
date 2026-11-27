'use strict';
const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const os = require('node:os');
const root=path.resolve(__dirname,'../..');
const renderer=path.join(root,'dependencies/managed/packages/documentation/build/renderer');
const { copyAssets, prepareSite, stageFavicon } = require(path.join(renderer,'build.cjs'));

test('Native Astro renderer owns routing and layout without a documentation theme framework', () => {
  const manifest = require(path.join(renderer,'package.json'));
  assert.equal(manifest.private,true);
  assert.ok(manifest.dependencies.astro);
  assert.ok(manifest.dependencies['@astrojs/mdx']);
  assert.ok(manifest.dependencies['astro-expressive-code']);
  assert.ok(!manifest.dependencies['@astrojs/starlight']);
  const astro=fs.readFileSync(path.join(renderer,'astro.config.mjs'),'utf8');
  const collection=fs.readFileSync(path.join(renderer,'src/content.config.mjs'),'utf8');
  const route=fs.readFileSync(path.join(renderer,'src/pages/[...slug].astro'),'utf8');
  const shell=fs.readFileSync(path.join(renderer,'src/components/PageFrame.astro'),'utf8');
  assert.ok(astro.includes("resolve(here, 'dist')"));
  assert.ok(fs.readFileSync(path.join(renderer,'build.cjs'),'utf8').includes('build/github/pages'));
  assert.match(collection,/glob\(/);
  assert.match(route,/getStaticPaths/);
  assert.match(route,/await render\(entry\)/);
  assert.match(shell,/<main id="main"/);
  assert.match(shell,/import '\.\.\/styles\/project\.css'/);
  assert.match(shell,/images\/favicon\.png/);
  assert.match(astro,/themes: \['github-dark'\]/);
  assert.doesNotMatch(astro,/@astrojs\/starlight/);
  const signature=fs.readFileSync(path.join(root,'content/images/favicon.png')).subarray(0,8).toString('hex');
  assert.equal(signature,'89504e470d0a1a0a');
  assert.ok(fs.existsSync(path.join(root,'content/theme.css')));
  const layout=fs.readFileSync(path.join(renderer,'src/styles/layout.css'),'utf8');
  assert.match(layout,/--docs-article-width:\s*883px/);
  assert.ok(!layout.includes('--sl-color-bg:'));
});

test('Measured dark palette, independent presentation layers and forced colors', () => {
  const shell = fs.readFileSync(path.join(renderer, 'src/components/PageFrame.astro'), 'utf8');
  const entries = [...shell.matchAll(/['"](\.\.\/styles\/[^'"]+\.css)['"]/g)].map(match => match[1].replace('../styles/','./src/styles/'));
  assert.deepEqual(entries, [
    './src/styles/theme/fallback.css',
    './src/styles/layout.css',
    './src/styles/typography.css',
    './src/styles/navigation.css',
    './src/styles/reference.css',
    './src/styles/project.css',
    './src/styles/theme/forced-colors.css',
  ]);
  const fallback = fs.readFileSync(path.join(renderer, 'src/styles/theme/fallback.css'), 'utf8');
  const forced = fs.readFileSync(path.join(renderer, 'src/styles/theme/forced-colors.css'), 'utf8');
  assert.match(fallback, /--docs-surface: #121215;/);
  assert.match(fallback, /--docs-link: #528bff;/);
  assert.match(fallback, /color-scheme: dark;/);
  assert.doesNotMatch(fallback, /data-theme=['"]light|color-scheme: light/);
  assert.match(forced, /@media \(forced-colors: active\)/);
  assert.match(forced, /--docs-selected: Highlight;/);
  const tokens = css => [...new Set([...css.matchAll(/(--(?:docs|sl-color)-[a-z0-9-]+):/g)].map(match => match[1]))].sort();
  assert.deepEqual(tokens(forced), tokens(fallback));
  assert.match(shell, /data-theme="dark"/);
  const example = fs.readFileSync(path.join(root, 'content/docs/base-part.mdx'), 'utf8');
  assert.match(example, /<ApiSummary .*members=/);
  assert.match(example, /\x60\x60\x60luau/);
});

test('Static image copier preserves nested paths', t => {
  const tmp = fs.mkdtempSync(path.join(os.tmpdir(), 'docs-assets-'));
  t.after(() => fs.rmSync(tmp, { recursive: true, force: true }));
  const from = path.join(tmp, 'from'), to = path.join(tmp, 'to');
  fs.mkdirSync(path.join(from, 'nested'), { recursive: true });
  fs.writeFileSync(path.join(from, 'nested/logo.svg'), 'image');
  copyAssets(from, to);
  assert.equal(fs.readFileSync(path.join(to, 'nested/logo.svg'), 'utf8'), 'image');
  assert.ok(fs.existsSync(path.join(root, 'content/docs/index.mdx')));
});

test('Content staging creates a flat docs root, excludes repository templates and copies the project theme', t => {
  const temporary = fs.mkdtempSync(path.join(os.tmpdir(), 'docs-stage-'));
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
  const temp = fs.mkdtempSync(path.join(os.tmpdir(), 'docs-favicon-'));
  t.after(() => fs.rmSync(temp, { recursive: true, force: true }));
  const source = path.join(root, 'content/images/favicon.png');
  const destination = path.join(temp, 'public/images/favicon.png');
  stageFavicon(source, destination);
  assert.deepEqual(fs.readFileSync(destination), fs.readFileSync(source));
  assert.throws(() => stageFavicon(path.join(temp, 'missing.png'), destination),
    /Missing or invalid authored favicon/);
});

 test('API reference components use project type metadata and registered member anchors', () => {
  const example = fs.readFileSync(path.join(root,'content/docs/base-part.mdx'),'utf8');
  const ids = [...example.matchAll(/<ApiMember [^>]*id="([^"]+)"/g)].map(m=>m[1]);
  const summary = [...example.matchAll(/"href":"#([^"]+)"/g)].map(m=>m[1]);
  assert.equal(ids.length, 106);
  assert.equal(new Set(ids).size, ids.length);
  assert.match(example, /^title: BasePart$/m);
  assert.deepEqual(summary.sort(),ids.sort());
  for(const id of ids) assert.ok(example.includes('### '+id+'\n'));
  const signature=fs.readFileSync(path.join(renderer,'src/components/ApiSignature.astro'),'utf8');
  assert.match(signature,/import builtins/);
  assert.doesNotMatch(signature,/Lorem ipsum/);
  assert.match(signature,/<a class="api-type"/);
  assert.match(signature,/<button type="button" class="api-type"/);
});

test('API icon families share captured geometry and exact colors without inventing constructors', () => {
  const icons = require(path.join(renderer,'src/data/api-icons.json'));
  assert.deepEqual(Object.keys(icons).sort(), ['event','method','property']);
  assert.deepEqual([icons.property.color,icons.method.color,icons.event.color], ['#1AC8FF','#E26CF4','#F2BA2A']);
  assert.deepEqual([icons.property.paths.length,icons.method.paths.length,icons.event.paths.length],[1,6,1]);
  const component = fs.readFileSync(path.join(renderer,'src/components/ApiIcon.astro'),'utf8');
  assert.match(component,/callback: 'method'/);
  assert.match(component,/signal: 'event'/);
  assert.match(component,/icon && <svg/);
});

test('multiline callable signatures preserve nested parentheses and return tuples', async () => {
  const {formatSignature}=await import(require('node:url').pathToFileURL(path.join(renderer,'src/data/format-signature.mjs')).href);
  assert.deepEqual(formatSignature('Get(key: string, fn: (x: number) -> boolean): (unknown, boolean)'),{before:'Get(',args:'key: string, fn: (x: number) -> boolean',after:'): (unknown, boolean)'});
  assert.equal(formatSignature('Value: string'),null);
  assert.equal(formatSignature('OnInvoke: (x: number) -> boolean'),null);
  assert.equal(formatSignature('new()'),null);
});

test('shared TOC is a renderer override, not two competing scrollspies', () => {
  const shell=fs.readFileSync(path.join(renderer,'src/components/PageFrame.astro'),'utf8');
  assert.match(shell,/<TableOfContents toc=\{toc\}/);
  assert.match(shell,/<MobileTableOfContents toc=\{toc\}/);
  const controller=fs.readFileSync(path.join(renderer,'src/components/TocController.astro'),'utf8');
  assert.match(controller,/getBoundingClientRect\(\)\.top<=threshold/);
  assert.match(controller,/link\.removeAttribute\('aria-current'\)/);
});

test('scroll padding is the only anchor offset', () => {
  const css=fs.readFileSync(path.join(renderer,'src/styles/typography.css'),'utf8');
  assert.match(css,/scroll-padding-top:var\(--docs-anchor-offset\)/);
  assert.doesNotMatch(css,/scroll-margin-top:\s*var\(--docs-anchor-offset/);
});

test('reference title and member panels use the captured component structure',()=>{
  const title=fs.readFileSync(path.join(renderer,'src/components/PageTitle.astro'),'utf8');
  const member=fs.readFileSync(path.join(renderer,'src/components/ApiMember.astro'),'utf8');
  assert.match(title,/<div class="titleRow">\s*<div class="titleContainer">\s*<span class="MuiTypography-root Typography-h1-Typography-root-title MuiTypography-inherit"/);
  assert.match(title,/role="heading" aria-level="1"/);
  assert.match(member,/class="MuiTypography-root Typography-body1-Typography-root-signatureContainer MuiTypography-inherit"/);
  const panel=fs.readFileSync(path.join(renderer,'src/components/ApiPanelSignature.astro'),'utf8');
  assert.match(member,/<ApiPanelSignature/);
  assert.match(panel,/<div class="multilineSignature">[\s\S]*?<div class="parametersContainer">/);
  assert.doesNotMatch(member,/class="api-signature-panel"/);
});
