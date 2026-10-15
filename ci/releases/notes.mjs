import fs from 'node:fs';
import { escapeMarkdown, policy } from './core.mjs';

export async function releaseNotes(selection, data, repoURL, api) {
  const linked = new Map(), covered = new Set();
  if (api) {
    // Resolve associations from GitHub rather than guessing PR numbers from subjects.
    for (let offset = 0; offset < data.commits.length; offset += 8) {
      await Promise.all(data.commits.slice(offset, offset + 8).map(async commit => {
        const pulls = await api.pages(`/commits/${commit.sha}/pulls`);
        for (const pr of pulls) {
          if (!pr.merged_at || pr.base?.ref !== 'source' || pr.base?.repo?.html_url !== repoURL) continue;
          if (!data.commits.some(entry => entry.sha === pr.merge_commit_sha)) continue;
          linked.set(pr.number, pr); covered.add(commit.sha);
        }
      }));
    }
  }
  const lines = [...linked.values()].sort((a, b) => a.number - b.number).map(pr =>
    `- ${escapeMarkdown(pr.title)} by @${pr.user.login} in [#${pr.number}](${repoURL}/pull/${pr.number})`);
  const direct = data.commits.filter(commit => !covered.has(commit.sha));
  const introduction = selection.notes ? fs.readFileSync(selection.notes, 'utf8').trim() + '\n\n' : '';
  let notes = introduction + `## What's Changed\n\n`;
  notes += lines.join('\n') || (direct.length ? 'Changes were pushed directly to source.' : 'No changes in this range.');
  if (direct.length) {
    notes += `\n\n<details>\n<summary>Direct changes (${direct.length})</summary>\n\n`
      + direct.slice(0, policy.body_commit_limit).map(commit => `- [${escapeMarkdown(commit.subject)}](${commit.url})`).join('\n')
      + '\n\n</details>';
  }
  const compare = selection.from === 'beginning' ? `${repoURL}/commits/${selection.source_sha}`
    : `${repoURL}/compare/${selection.from}...${selection.source_sha}`;
  const label = selection.from === 'beginning' ? 'Source history' : `${selection.from.slice(0, 7)}...${selection.source_sha.slice(0, 7)}`;
  notes += `\n\n**Full Changelog**: [${label}](${compare})\n`;
  if (data.coauthors?.length) notes += '\n---\n\n' + data.coauthors.map(name => `Co-authored-by: ${escapeMarkdown(name)}`).join('  \n') + '\n';
  return notes;
}
