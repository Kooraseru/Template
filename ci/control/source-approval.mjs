import fs from 'node:fs';

// Authorization to execute is separate from proof that a build succeeded.
// Query GitHub's merge metadata instead of inferring approval from commit text.
export function sourceApproval(env, { api, isAdmin }) {
  if (env.ACT === 'true' || env.GITHUB_ACTIONS !== 'true' || env.GITHUB_SERVER_URL !== 'https://github.com'
      || env.GITHUB_EVENT_NAME !== 'push' || env.GITHUB_REF !== 'refs/heads/source') return null;
  const sha = env.GITHUB_SHA, repo = env.GITHUB_REPOSITORY;
  if (!/^[a-f0-9]{40}$/.test(sha || '') || !/^[^/\s]+\/[^/\s]+$/.test(repo || '')) return null;
  if (env.GITHUB_EVENT_PATH) {
    const event = JSON.parse(fs.readFileSync(env.GITHUB_EVENT_PATH, 'utf8'));
    if (event.deleted || event.after !== sha || event.ref !== env.GITHUB_REF
        || event.repository?.full_name?.toLowerCase() !== repo.toLowerCase()) return null;
  }
  // Requiring an admin run actor also preserves receipt verification's authority boundary.
  if (!isAdmin(env.GITHUB_ACTOR)) return null;
  for (let page = 1; ; page++) {
    const pulls = api(`repos/${repo}/commits/${sha}/pulls?per_page=100&page=${page}`);
    for (const candidate of pulls) {
      if (candidate.merge_commit_sha !== sha || !candidate.merged_at || candidate.base?.ref !== 'source'
          || candidate.base.repo?.full_name?.toLowerCase() !== repo.toLowerCase()) continue;
      const pr = api(`repos/${repo}/pulls/${candidate.number}`);
      if (pr.merged && pr.merge_commit_sha === sha && pr.base?.ref === 'source'
          && pr.base.repo?.full_name?.toLowerCase() === repo.toLowerCase() && isAdmin(pr.merged_by?.login)) {
        return { kind: 'admin-merge', actor: env.GITHUB_ACTOR, merged_by: pr.merged_by.login,
          pr: pr.number, source_sha: sha };
      }
    }
    if (pulls.length < 100) break;
  }
  return { kind: 'admin-source-push', actor: env.GITHUB_ACTOR, source_sha: sha };
}
