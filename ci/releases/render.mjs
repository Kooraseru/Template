import fs from 'node:fs';
import path from 'node:path';
import { command, git, write, sha256, canonical, history, layout, escapeHTML, escapeMarkdown, verifyDistribution, policy } from './core.mjs';

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
export function htmlGraph(rows, channel, sha) {
  const graph = svg(rows, true);
  const targets = rows.map((row, index) => `<a href="${escapeHTML(row.url)}" target="_blank" rel="noopener noreferrer" title="${escapeHTML(`${row.sha}\n${row.subject}\n${row.name || ''}\n${row.date || ''}`)}" style="top:${index * 34 + 11}px;height:34px"><span class="sr">${escapeHTML(row.sha + ' ' + row.subject)}</span></a>`).join('');
  return `<!doctype html><html lang="en"><meta charset="utf-8"><meta name="viewport" content="width=device-width"><title>${escapeHTML(channel)} commit graph</title><style>body{background:#0d1117;color:#e6edf3;font:14px monospace;margin:24px}a{color:#58a6ff}.graph{position:relative;width:max-content}.graph>a{position:absolute;left:0;width:100%;display:block}.graph>a:hover{background:#58a6ff22;outline:1px solid #58a6ff}.sr{position:absolute;width:1px;height:1px;overflow:hidden;clip:rect(0,0,0,0)}</style><h1>${escapeHTML(channel)}</h1><p>Selected source commit: ${escapeHTML(sha)}</p><p>Hover a row for details; select it to open the commit. Scroll to inspect the complete graph.</p><div class="graph">${graph}${targets}</div></html>`;
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
export function finalizeAssets(root, metadata, files) {
  const prefix = `${metadata.channel}-${metadata.source_sha}`;
  // Compute the staging identity before inserting it into linked asset names.
  const preimage = files.map(file => ({ path: file, sha256: sha256(fs.readFileSync(`${root}/${file}`)) }));
  metadata.generation = sha256(canonical({ source: metadata.source_sha, selection: metadata.selection_hash,
    targets: metadata.targets, content: preimage })).slice(0, 16);
  const notes = fs.readFileSync(`${root}/notes.md`, 'utf8').replaceAll(`${prefix}-`, `${prefix}-${metadata.generation}-`);
  write(`${root}/notes.md`, notes);
  metadata.assets = files.map(file => ({ path: file, name: `${prefix}-${metadata.generation}-${path.basename(file)}`,
    sha256: sha256(fs.readFileSync(`${root}/${file}`)) }));
  write(`${root}/release.json`, metadata);
  return metadata;
}
export async function assemble(plan) {
  const repo = process.env.GITHUB_REPOSITORY || git(['remote', 'get-url', 'origin']).replace(/^.*github\.com[:/]/, '').replace(/\.git$/, '');
  const repoURL = `https://github.com/${repo}`;
  for (const selection of plan.selections) {
    const root = `build/releases/${selection.channel}/${selection.source_sha}`;
    fs.rmSync(root, { recursive: true, force: true });
    fs.mkdirSync(`${root}/packages`, { recursive: true });
    const entries = plan.builds.filter(entry => entry.source_sha === selection.source_sha);
    if (!entries.length) throw Error(`No selected build targets for ${selection.channel}`);
    const targets = [];
    for (const entry of entries) {
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
    renderPNGs(graphDir);
    // Public graph JSON deliberately excludes canonical email and raw commit bodies.
    const publicRows = rows.map(row => {
      const publicRow = { ...row };
      delete publicRow.email; delete publicRow.body;
      return publicRow;
    });
    write(`${root}/graph.json`, publicRows);
    write(`${root}/graph.html`, htmlGraph(publicRows, selection.channel, selection.source_sha));
    const prefix = `${selection.channel}-${selection.source_sha}`;
    const assetURL = file => `${repoURL}/releases/download/${selection.channel}/${prefix}-${file}`;
    const changes = data.commits.map(commit => `- [${commit.sha.slice(0, 7)}](${commit.url}) ${escapeMarkdown(commit.subject)}`).join('\n');
    const compareURL = selection.from === 'beginning' ? `${repoURL}/commits/${selection.source_sha}` : `${repoURL}/compare/${selection.from}...${selection.source_sha}`;
    write(`${root}/changes.md`, `# Changes\n\n${changes || 'No commits in this range.'}\n\n\`\`\`text\n${data.stats}\n\`\`\`\n`);
    const introduction = selection.notes ? fs.readFileSync(selection.notes, 'utf8').trim() + '\n\n' : '';
    const notes = introduction + `Selected source commit: [\`${selection.source_sha}\`](${repoURL}/commit/${selection.source_sha})\n\n`
      + `## Changes\n\n[View the range](${compareURL}) · ${data.commits.length} commits\n\n${escapeMarkdown(data.shortstat || 'No changed files.')}\n\n`
      + data.commits.slice(0, policy.body_commit_limit).map(commit => `- [${commit.sha.slice(0, 7)}](${commit.url}) ${escapeMarkdown(commit.subject)}`).join('\n')
      + `\n\n[Complete changes and file statistics](${assetURL('changes.md')})\n\n`
      + `## Commit graph\n\n${pages.map(name => `![Commit graph](${assetURL(name + '.png')})`).join('\n\n')}\n\n`
      + `[Interactive graph](${assetURL('graph.html')}) · [Repository graph](${repoURL}/network)\n\n`
      + `## Contributors\n\n${data.contributors.map(name => `- ${escapeMarkdown(name)}`).join('\n') || 'No contributors in this range.'}\n`;
    write(`${root}/notes.md`, notes);
    command('tar', ['-czf', `${root}/packages.tar.gz`, '-C', `${root}/packages`, '.']);
    const metadata = { schema: 1, ...selection, controller_sha: plan.controller_sha, controller_hash: plan.controller_hash, targets,
      prerelease: selection.channel !== 'stable', selection_hash: sha256(canonical(selection)),
      contract_hash: sha256(fs.readFileSync('ci/releases/channels.toml')), assets: [] };
    const assetFiles = ['packages.tar.gz', 'notes.md', 'changes.md', 'graph.html', 'graph.json', ...pages.map(name => `graph/${name}.png`)];
    finalizeAssets(root, metadata, assetFiles);
    console.log(`Assembled ${selection.channel} at ${selection.source_sha} with ${targets.length} targets`);
  }
}
