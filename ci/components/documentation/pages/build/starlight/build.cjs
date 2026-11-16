'use strict';
// A component-owned entry point for Starlight. The CI system sees only the site output.
const fs = require('node:fs');
const path = require('node:path');
const { spawnSync } = require('node:child_process');
const root = path.resolve(__dirname, '../../../../../..');
const site = __dirname;
const output = path.join(root, 'build/github/pages');
const staging = path.join(site, 'dist');
const docs = path.join(root, 'content/docs');
const images = path.join(root, 'content/images');
const theme = path.join(root, 'content/theme.css');
const stagedDocs = path.join(site, 'src/content/docs');
const stagedTheme = path.join(site, 'src/styles/project.css');
const favicon = path.join(images, 'favicon.png');
const stagedFavicon = path.join(site, 'public/images/favicon.png');

function stageFavicon(input = favicon, destination = stagedFavicon) {
  if (!fs.existsSync(input) || fs.lstatSync(input).isSymbolicLink() ||
      !fs.statSync(input).isFile()) {
    throw new Error('Missing or invalid authored favicon: ' + input);
  }
  fs.mkdirSync(path.dirname(destination), { recursive: true });
  if (fs.existsSync(destination) && fs.lstatSync(destination).isSymbolicLink())
    throw new Error('Refusing symlinked staged favicon: ' + destination);
  fs.copyFileSync(input, destination);
  return destination;
}


function assertDirectory(input) {
  if (!fs.existsSync(input) || fs.lstatSync(input).isSymbolicLink() || !fs.statSync(input).isDirectory())
    throw new Error('Expected a non-symlink documentation directory: ' + input);
}

function stageDocs(source, destination, skipRepository = false) {
  assertDirectory(source);
  fs.mkdirSync(destination, { recursive: true });
  for (const entry of fs.readdirSync(source, { withFileTypes: true })) {
    if (entry.isSymbolicLink()) throw new Error('Refusing linked documentation source: ' + entry.name);
    if (skipRepository && entry.name === 'repository') continue;
    const from = path.join(source, entry.name), to = path.join(destination, entry.name);
    if (entry.isDirectory()) stageDocs(from, to);
    else if (entry.isFile() && /\.(?:md|mdx|mdoc)$/.test(entry.name)) fs.copyFileSync(from, to);
  }
}

function prepareSite(options = {}) {
  const source = options.docs || docs;
  const staged = options.stagedDocs || stagedDocs;
  const themeFile = options.theme || theme;
  const stagedCss = options.stagedTheme || stagedTheme;
  assertDirectory(source);
  if (fs.existsSync(staged)) {
    if (fs.lstatSync(staged).isSymbolicLink()) throw new Error('Refusing linked Starlight staging directory');
    fs.rmSync(staged, { recursive: true });
  }
  stageDocs(source, staged, true);
  if (!fs.existsSync(path.join(staged, 'index.md')))
    throw new Error('Missing staged documentation homepage');
  fs.mkdirSync(path.dirname(stagedCss), { recursive: true });
  if (fs.existsSync(themeFile)) {
    if (fs.lstatSync(themeFile).isSymbolicLink() || !fs.statSync(themeFile).isFile())
      throw new Error('Refusing invalid project theme: ' + themeFile);
    fs.copyFileSync(themeFile, stagedCss);
  } else {
    fs.writeFileSync(stagedCss, '/* No project theme override. */\n');
  }
  const stagedIcon = stageFavicon(options.favicon || favicon, options.stagedFavicon || stagedFavicon);
  return { staged, stagedCss, stagedIcon };
}


function run(program, args, cwd = root) {
  const result = spawnSync(program, args, { cwd, stdio: 'inherit', shell: false,
    windowsHide: true, timeout: 300_000, env: { ...process.env, ELECTRON_RUN_AS_NODE: '1' } });
  if (result.error || result.status !== 0) {
    throw new Error(program + ' failed: ' + (result.error?.message || 'exit ' + result.status));
  }
}

function copyAssets(source, destination) {
  if (!fs.existsSync(source)) return;
  if (!fs.lstatSync(source).isDirectory()) throw new Error('Invalid image directory: ' + source);
  fs.mkdirSync(destination, { recursive: true });
  for (const entry of fs.readdirSync(source, { withFileTypes: true })) {
    if (entry.isSymbolicLink()) throw new Error('Refusing linked documentation asset: ' + entry.name);
    const from = path.join(source, entry.name), to = path.join(destination, entry.name);
    if (entry.isDirectory()) copyAssets(from, to);
    else if (entry.isFile() && entry.name !== '.gitkeep') fs.copyFileSync(from, to);
    else if (!entry.isFile()) throw new Error('Unsupported documentation asset: ' + from);
  }
}

function build() {
  prepareSite();
  if (fs.existsSync(output)) {
    if (fs.lstatSync(output).isSymbolicLink()) throw new Error('Refusing symlinked Pages output');
    fs.rmSync(output, { recursive: true });
  }
  const astroManifest = path.join(site, 'node_modules/astro/package.json');
  if (!fs.existsSync(astroManifest)) {
    // Exact direct versions are declared in the component's package.json.
    // This install is isolated from the workspace npm dependency loader.
    let npm = 'npm', args = ['install', '--no-audit', '--no-fund', '--no-package-lock'];
    if (process.platform === 'win32') {
      const candidates = [path.dirname(process.execPath), ...(process.env.PATH || '').split(path.delimiter)]
        .filter(Boolean).map(dir => path.join(dir, 'node_modules/npm/bin/npm-cli.js'));
      const cli = candidates.find(file => fs.existsSync(file));
      if (!cli) throw new Error('Cannot locate npm-cli.js');
      npm = process.execPath;
      args = [cli, ...args];
    }
    run(npm, args, site);
  }
  const installed = JSON.parse(fs.readFileSync(astroManifest, 'utf8'));
  const bin = typeof installed.bin === 'string' ? installed.bin : installed.bin?.astro;
  if (typeof bin !== 'string' || !bin) throw new Error('Astro installation has no CLI entry point');
  const cli = path.join(site, 'node_modules/astro', bin);
  if (!fs.existsSync(cli)) throw new Error('Missing Astro CLI: ' + cli);
  run(process.execPath, [cli, 'build', '--root', site]);
  // Keep dynamic prerender dependencies under the Starlight package while
  // compiling, then export plain static assets into the CI output contract.
  if (!fs.existsSync(path.join(staging, 'index.html'))) {
    throw new Error('Starlight did not produce dist/index.html');
  }
  fs.cpSync(staging, output, { recursive: true, force: true });
  copyAssets(images, path.join(output, 'images'));
  if (!fs.existsSync(path.join(output, 'index.html'))) {
    throw new Error('Starlight failed to produce build/github/pages/index.html');
  }
  process.stdout.write('Starlight: built ' + output + '\n');
}

module.exports = { build, prepareSite, stageFavicon, copyAssets, root, site, output, docs };
if (require.main === module) {
  try { if (process.argv.includes('--prepare')) prepareSite(); else build(); }
  catch (error) { console.error(String(error)); process.exitCode = 1; }
}
