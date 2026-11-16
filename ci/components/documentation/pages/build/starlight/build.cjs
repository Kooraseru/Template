'use strict';
// A component-owned entry point for Starlight. The CI system sees only the site output.
const fs = require('node:fs');
const path = require('node:path');
const { spawnSync } = require('node:child_process');
const root = path.resolve(__dirname, '../../../../../..');
const site = __dirname;
const output = path.join(root, 'build/github/pages');
const docs = path.join(root, 'content/docs');
const images = path.join(root, 'content/images');

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
  if (!fs.existsSync(path.join(docs, 'index.md'))) throw new Error('Missing content/docs/index.md');
  if (fs.existsSync(output)) {
    if (fs.lstatSync(output).isSymbolicLink()) throw new Error('Refusing symlinked Pages output');
    fs.rmSync(output, { recursive: true });
  }
  const executable = path.join(site, 'node_modules/astro/astro.js');
  if (!fs.existsSync(executable)) {
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
  run(process.execPath, [executable, 'build', '--root', site]);
  copyAssets(images, path.join(output, 'images'));
  if (!fs.existsSync(path.join(output, 'index.html'))) {
    throw new Error('Starlight failed to produce build/github/pages/index.html');
  }
  process.stdout.write('Starlight: built ' + output + '\n');
}

module.exports = { build, copyAssets, root, site, output, docs };
if (require.main === module) {
  try { build(); } catch (error) { console.error(String(error)); process.exitCode = 1; }
}
