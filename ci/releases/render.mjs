import fs from 'node:fs';
import { releaseNotes } from './notes.mjs';
import path from 'node:path';
import { command, git, write, sha256, canonical, history, layout, escapeHTML, escapeMarkdown, verifyDistribution, policy, normalizeArtifactDownload } from './core.mjs';

export function svg(rows, expanded = false) {
  const columns = Math.max(1, ...rows.map(row => Math.max(row.before.length, row.after.length)));
  const graphWidth = 24 + columns * 22;
  const labelFor = row => `${row.sha.slice(0, 7)}  ${row.subject} ${row.context ? '[range start]' : ''} ${row.refs.length ? '[' + row.refs.join(', ') + ']' : ''}`;
  const characters = expanded ? Math.max(116, ...rows.map(row => [...labelFor(row)].length)) : 116;
  const width = graphWidth + characters * 8 + 16, height = Math.max(64, rows.length * 34 + 28);
  const color = lane => policy.graph_colors[lane % policy.graph_colors.length];
  let content = `<rect width="100%" height="100%" rx="8" fill="#0d1117"/>`;
  for (const [index, row] of rows.entries()) {
    const y = 28 + index * 34, x = 24 + row.lane * 22;
    for (let lane = 0; lane < row.before.length; lane++) {
      if (row.before[lane] && lane !== row.lane) content += `<path d="M ${24 + lane * 22} ${y - 17} V ${y + 17}" stroke="${color(lane)}" stroke-width="2"/>`;
    }
    if (row.incoming) content += `<path d="M ${x} ${y - 17} V ${y}" stroke="${color(row.lane)}" stroke-width="2"/>`;
    for (const edge of row.edges) content += `<path d="M ${x} ${y} C ${x} ${y + 17}, ${24 + edge.to * 22} ${y}, ${24 + edge.to * 22} ${y + 17}" fill="none" stroke="${color(edge.to)}" stroke-width="2"/>`;
    content += `<circle cx="${x}" cy="${y}" r="5" fill="${row.context ? '#0d1117' : color(row.lane)}" stroke="${color(row.lane)}" stroke-width="2"/>`;
    const complete = [...labelFor(row)];
    const label = complete.length > characters ? complete.slice(0, characters - 1).join('') + '…' : complete.join('');
    content += `<text x="${graphWidth}" y="${y + 5}" fill="${row.context ? '#8b949e' : '#e6edf3'}" font-family="JetBrains Mono" font-size="13">${escapeHTML(label)}</text>`;
  }
  return `<svg xmlns="http://www.w3.org/2000/svg" width="${width}" height="${height}" viewBox="0 0 ${width} ${height}">${content}</svg>`;
}
export function htmlGraph(rows, version, sha) {
  const graph = svg(rows, true);
  const targets = rows.map((row, index) => `<a href="${escapeHTML(row.url)}" target="_blank" rel="noopener noreferrer" title="${escapeHTML(`${row.sha}\n${row.subject}\n${row.name || ''}\n${row.date || ''}`)}" style="top:${index * 34 + 11}px;height:34px"><span class="sr">${escapeHTML(row.sha + ' ' + row.subject)}</span></a>`).join('');
  return `<!doctype html><html lang="en"><meta charset="utf-8"><meta name="viewport" content="width=device-width"><title>${escapeHTML(version)} commit graph</title><style>body{background:#0d1117;color:#e6edf3;font:14px monospace;margin:24px}a{color:#58a6ff}.graph{position:relative;width:max-content}.graph>a{position:absolute;left:0;width:100%;display:block}.graph>a:hover{background:#58a6ff22;outline:1px solid #58a6ff}.sr{position:absolute;width:1px;height:1px;overflow:hidden;clip:rect(0,0,0,0)}</style><h1>${escapeHTML(version)}</h1><p>Selected source commit: ${escapeHTML(sha)}</p><p>Hover a row for details; select it to open the commit. Scroll to inspect the complete graph.</p><div class="graph">${graph}${targets}</div></html>`;
}
function renderPNGs(root) {
  const context = 'build/tmp/release-renderer';
  fs.mkdirSync(context, { recursive: true });
  for (const file of ['package.json', 'package-lock.json', 'render-png.mjs']) fs.copyFileSync(`ci/releases/${file}`, `${context}/${file}`);
  fs.copyFileSync('ci/images/release-renderer/JetBrainsMono-Regular.ttf', `${context}/JetBrainsMono-Regular.ttf`);
  const toolFiles = ['package.json', 'package-lock.json', 'render-png.mjs', 'JetBrainsMono-Regular.ttf'];
  const identity = sha256(canonical([...toolFiles.map(file => sha256(fs.readFileSync(`${context}/${file}`))),
    sha256(fs.readFileSync('ci/images/release-renderer/Dockerfile'))])).slice(0, 24);
  const tag = `template-ci/release-renderer:${identity}`;
  command('docker', ['build', '--file', 'ci/images/release-renderer/Dockerfile', '--tag', tag, context], { stdio: 'inherit' });
  const container = command('docker', ['create', tag]).trim();
  try {
    command('docker', ['cp', `${root}/.`, `${container}:/input`]);
    command('docker', ['start', '--attach', container], { stdio: 'inherit' });
    command('docker', ['cp', `${container}:/output/.`, root]);
  } finally { command('docker', ['rm', '--force', container]); }
}
// Inspect packaged payloads, never compiler probes or internal reports.
export function isExecutable(bytes) {
  if (bytes.length < 4) return false;
  if (bytes.subarray(0, 2).toString() === '#!') return true;
  if (bytes.subarray(0, 4).equals(Buffer.from([0x7f, 0x45, 0x4c, 0x46]))) {
    if (bytes.length < 18) return false;
    const type = bytes[5] === 2 ? bytes.readUInt16BE(16) : bytes.readUInt16LE(16);
    if (type === 2) return true;
    // PIE has PT_INTERP; a shared library does not. Reject malformed offsets.
    if (type !== 3 || ![1, 2].includes(bytes[4]) || bytes.length < 64) return false;
    const little = bytes[5] === 1;
    const u16 = offset => little ? bytes.readUInt16LE(offset) : bytes.readUInt16BE(offset);
    const u32 = offset => little ? bytes.readUInt32LE(offset) : bytes.readUInt32BE(offset);
    const wide = bytes[4] === 2;
    const offset = wide ? Number(little ? bytes.readBigUInt64LE(32) : bytes.readBigUInt64BE(32)) : u32(28);
    const size = u16(wide ? 54 : 42), count = u16(wide ? 56 : 44);
    if (size < 4 || !Number.isSafeInteger(offset) || offset + size * count > bytes.length) return false;
    for (let i = 0; i < count; i++) if (u32(offset + i * size) === 3) return true;
    return false;
  }
  if (bytes[0] === 0x4d && bytes[1] === 0x5a && bytes.length >= 64) {
    const offset = bytes.readUInt32LE(60);
    return offset + 24 <= bytes.length && bytes.readUInt32LE(offset) === 0x4550
      && !(bytes.readUInt16LE(offset + 22) & 0x2000);
  }
  const magic = bytes.readUInt32BE(0);
  if ([0xfeedface, 0xfeedfacf, 0xcefaedfe, 0xcffaedfe].includes(magic) && bytes.length >= 16) {
    return ([0xcefaedfe, 0xcffaedfe].includes(magic) ? bytes.readUInt32LE(12) : bytes.readUInt32BE(12)) === 2;
  }
  return false;
}

export function finalizeAssets(root, metadata, files) {
  metadata.assets = files.map(file => ({ path: file, name: `${metadata.version}-${path.basename(file)}`,
    sha256: sha256(fs.readFileSync(`${root}/${file}`)) }));
  if (new Set(metadata.assets.map(asset => asset.name)).size !== files.length) throw Error('Duplicate public asset names');
  write(`${root}/release.json`, metadata);
  return metadata;
}
export function packageArchive(root) {
  // Assembly runs on Ubuntu. Normalize tar metadata so receipt restoration times
  // and file ownership do not change the contents of a repeated assembly.
  command('tar', ['--sort=name', '--mtime=@0', '--owner=0', '--group=0', '--numeric-owner', '--format=gnu',
    '-czf', `${root}/packages.tar.gz`, '-C', `${root}/packages`, '.']);
}
export async function assemble(plan, { render = renderPNGs, archive = packageArchive, notesAPI } = {}) {
  const repo = process.env.GITHUB_REPOSITORY || git(['remote', 'get-url', 'origin']).replace(/^.*github\.com[:/]/, '').replace(/\.git$/, '');
  const repoURL = `https://github.com/${repo}`;
  for (const selection of plan.selections) {
    const root = `build/releases/${selection.version}`;
    fs.rmSync(root, { recursive: true, force: true });
    fs.mkdirSync(`${root}/packages`, { recursive: true });
    const entries = plan.builds.filter(entry => entry.source_sha === selection.source_sha);
    if (!entries.length) throw Error(`No selected build targets for ${selection.version}`);
    const targets = [];
    for (const entry of entries) {
      if (plan.builds.length === 1) normalizeArtifactDownload('build/distributions', entry.artifact, 'provenance.json');
      const input = `build/distributions/${entry.artifact}`;
      const verified = verifyDistribution(input, entry);
      fs.cpSync(input, `${root}/packages/${entry.name}`, { recursive: true });
      targets.push({ name: entry.name, fingerprint: entry.fingerprint, manifest: verified.manifest,
        tested_sha:verified.metadata.source_sha, selected_sha:entry.source_sha, reuse_identity:entry.reuse_identity || 'exact_commit',
        contract: { name:entry.name, source_sha:entry.source_sha, tree:entry.tree,
          source_manifest_sha256:entry.source_manifest_sha256, fingerprint:entry.fingerprint,
          reuse_identity:entry.reuse_identity || 'exact_commit', runner:entry.runner, target:entry.target,
          ...(entry.accepted ? {accepted:entry.accepted} : {}) } });
    }
    const data = history(selection, '.', repoURL);
    const rows = layout([...data.commits, ...(data.context ? [data.context] : [])]);
    const graphDir = `${root}/graph`;
    fs.mkdirSync(graphDir, { recursive: true });
    const pages = [];
    for (let offset = 0; offset < rows.length; offset += policy.graph_rows_per_page) {
      const name = `graph-${String(pages.length + 1).padStart(3, '0')}`;
      write(`${graphDir}/${name}.svg`, svg(rows.slice(offset, offset + policy.graph_rows_per_page)));
      pages.push(name);
    }
    if (!pages.length) { write(`${graphDir}/graph-001.svg`, svg([])); pages.push('graph-001'); }
    render(graphDir);
    // Public graph JSON deliberately excludes canonical email and raw commit bodies.
    const publicRows = rows.map(row => {
      const publicRow = { ...row };
      delete publicRow.email; delete publicRow.body;
      return publicRow;
    });
    write(`${root}/graph.json`, publicRows);
    write(`${root}/graph.html`, htmlGraph(publicRows, selection.version, selection.source_sha));
    const changes = data.commits.map(commit => `- [${commit.sha.slice(0, 7)}](${commit.url}) ${escapeMarkdown(commit.subject)}`).join('\n');
    write(`${root}/changes.md`, `# Changes\n\n${changes || 'No commits in this range.'}\n\n${data.stats}\n`);
    const api = notesAPI !== undefined ? notesAPI : process.env.GH_TOKEN ? (await import('./publish.mjs')).client(process.env.GH_TOKEN, repo) : null;
    if (notesAPI === undefined && process.env.GITHUB_ACTIONS === 'true' && !api) throw Error('Hosted release notes require GitHub PR access');
    const notes = await releaseNotes(selection, data, repoURL, api);
    write(`${root}/notes.md`, notes);
    archive(root);
    // Internal release metadata contains product identity, not transient receipt locations
    // or the current publishing run. The latter stay in an internal manifest.
    const metadata = { schema: 2, ...selection, targets: targets.map(({contract, ...target}) => target), assets: [] };
    write(`${root}/publication.json`, { version: selection.version, source_sha: selection.source_sha,
      controller_sha: plan.controller_sha, controller_hash: plan.controller_hash, targets,
      contract_hash: sha256(fs.readFileSync('ci/releases/versions.toml')) });
    const assetFiles = [];
    for (const target of targets) {
      for (const item of target.manifest) {
        const input = `${root}/packages/${target.name}/${item.path}`;
        if (!isExecutable(fs.readFileSync(input))) continue;
        const file = `executables/${target.name}-${item.path.replaceAll('/', '-')}`;
        fs.mkdirSync(`${root}/executables`, { recursive: true });
        fs.copyFileSync(input, `${root}/${file}`);
        assetFiles.push(file);
      }
    }
    finalizeAssets(root, metadata, assetFiles);
    console.log(`Assembled ${selection.version} at ${selection.source_sha} with ${targets.length} targets`);
  }
}
