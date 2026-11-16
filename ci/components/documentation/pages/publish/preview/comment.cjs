'use strict';
// An idempotent GitHub Actions bot comment on the PR Conversation tab.
// Never post a preview link until Cloudflare returns successful deployment.
// Never edit comments by other authors, even if they copy the marker.
const { api } = require('../../../../../github/workflows/launch.cjs');

const marker = '<!-- template-ci:documentation-preview:v1 -->';
const botId = 41898282; // github-actions[bot]
const shaPattern = /^[0-9a-f]{40}$/;
const repoPattern = /^[A-Za-z0-9_.-]+\/[A-Za-z0-9_.-]+$/;

function bodyFor(config, candidate, closed) {
  if (candidate.type !== 'pr' ||
      !Number.isSafeInteger(candidate.number) || candidate.number < 1 ||
      candidate.alias !== 'pr-' + candidate.number ||
      !repoPattern.test(config.repo || '') ||
      !/^[a-z0-9][a-z0-9-]{0,62}$/.test(config.cloudflare_project || '') ||
      !/^\/(?:[a-zA-Z0-9._~-]+\/)*$/.test(config.base || '')) {
    throw new Error('Invalid PR preview comment identity');
  }
  const headline = '### Documentation preview';
  if (closed) {
    return [
      marker,
      headline,
      '**Status:** Closed – the preview alias has been retired.',
      '',
      'The temporary preview is no longer available. This comment is managed by CI.',
    ].join('\n');
  }
  if (!shaPattern.test(candidate.sha || ''))
    throw new Error('Cannot announce a preview without its published revision');
  const address = 'https://' + candidate.alias + '.' +
    config.cloudflare_project + '.pages.dev' + config.base;
  return [
    marker,
    headline,
    '**Website:** [Open preview](' + address + ')',
    '',
    '**Revision:** [' + candidate.sha.slice(0, 12) + '](https://github.com/' +
      config.repo + '/commit/' + candidate.sha + ')',
    '',
    'Hosted on Cloudflare Pages. CI updates this comment after each successful preview deployment and retires it when the PR closes.',
  ].join('\n');
}

function owned(comment) {
  return comment && Number.isSafeInteger(comment.id) &&
    (comment.user?.id === botId || comment.user?.login === 'github-actions[bot]') &&
    typeof comment.body === 'string' && comment.body.includes(marker);
}

async function findOwned(config, candidate, env, request) {
  const url = '/repos/' + config.repo + '/issues/' + candidate.number + '/comments';
  for (let page = 1; page <= 20; page++) {
    const result = await request('GET', url + '?per_page=100&page=' + page,
      env.GH_TOKEN, undefined, env);
    if (!Array.isArray(result)) throw new Error('Invalid PR comments API response');
    const existing = result.find(owned);
    if (existing) return existing;
    if (result.length < 100) return null;
  }
  throw new Error('PR has too many comments to safely find the existing preview note');
}

async function syncComment(config, candidate, env = process.env, closed = false, request = api) {
  if (candidate.type !== 'pr') return null; // Branch previews have no PR thread.
  if (!env.GH_TOKEN) throw new Error('Missing GitHub PR comment token');
  const body = bodyFor(config, candidate, closed);
  const previous = await findOwned(config, candidate, env, request);
  if (previous && previous.body === body) return { id: previous.id, action: 'unchanged' };
  if (previous) {
    await request('PATCH', '/repos/' + config.repo + '/issues/comments/' + previous.id,
      env.GH_TOKEN, { body }, env);
    return { id: previous.id, action: 'updated' };
  }
  if (closed) return null; // Don't post a new comment merely to announce removal.
  const created = await request('POST',
    '/repos/' + config.repo + '/issues/' + candidate.number + '/comments',
    env.GH_TOKEN, { body }, env);
  if (!Number.isSafeInteger(created?.id))
    throw new Error('GitHub did not return a preview comment ID');
  return { id: created.id, action: 'created' };
}

module.exports = { marker, bodyFor, owned, findOwned, syncComment };
