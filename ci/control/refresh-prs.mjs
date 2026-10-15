import fs from 'node:fs';
import { pathToFileURL } from 'node:url';
import { api, repository } from '../receipts/github.mjs';
import { pullRequestLabel } from './request.mjs';

const start = '        # BEGIN GENERATED PR CHOICES';
const end = '        # END GENERATED PR CHOICES';
export function renderChoices(source, pulls) {
  const begin = source.indexOf(start), finish = source.indexOf(end);
  if (begin < 0 || finish < begin || source.indexOf(start, begin + 1) >= 0) throw Error('PR dropdown markers missing or ambiguous');
  const choices = ['Source', ...pulls.filter(pr => pr.state === undefined || pr.state === 'open')
    .sort((a, b) => b.number - a.number).map(pullRequestLabel)];
  return source.slice(0, begin) + start + '\n        options:\n'
    + choices.map(choice => `          - ${JSON.stringify(choice)}\n`).join('') + source.slice(finish);
}

export function refresh(remote = false) {
  const repo = repository();
  const pulls = [];
  for (let page = 1; ; page++) {
    const entries = api(`repos/${repo}/pulls?state=open&base=source&per_page=100&page=${page}`);
    pulls.push(...entries);
    if (entries.length < 100) break;
  }
  const file = '.github/workflows/ci.yml';
  const original = remote ? api(`repos/${repo}/contents/${file}?ref=source`) : null;
  const before = original ? Buffer.from(original.content, 'base64').toString('utf8') : fs.readFileSync(file, 'utf8');
  const after = renderChoices(before, pulls);
  if (before === after) { console.log('PR dropdown is current'); return; }
  if (remote) {
    try {
      api(`repos/${repo}/contents/${file}`, 'PUT', { branch: 'source', sha: original.sha,
        message: 'Refresh CI pull request choices [skip ci]', content: Buffer.from(after).toString('base64') });
    } catch (error) {
      throw Error(`PR dropdown refresh could not update the protected workflow. Configure CI_WORKFLOW_TOKEN with workflow-file write permission and an allowed branch update path, or run node ci/control/refresh-prs.mjs locally and commit it. ${error.message}`);
    }
  } else fs.writeFileSync(file, after);
  console.log(`Refreshed PR dropdown with ${pulls.length} open PRs`);
}
if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) refresh(process.argv.includes('--remote'));
