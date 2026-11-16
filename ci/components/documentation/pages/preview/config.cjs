'use strict';

const fs = require('node:fs');
const path = require('node:path');
const crypto = require('node:crypto');

const root = path.resolve(__dirname, '../../../../..');
const shaPattern = /^[a-f0-9]{40}$/;
const repositoryPattern = /^[A-Za-z0-9_.-]+\/[A-Za-z0-9_.-]+$/;
const safeBranch = /^(?!\/)(?!.*(?:\.\.|\/\/|@\{|\\|[\x00-\x20~^:?*\[]))[A-Za-z0-9_./-]+$/;

function section(file, name) {
  const source = fs.readFileSync(file, 'utf8');
  let selected = false;
  const result = {};
  for (const raw of source.split(/\r?\n/)) {
    const line = raw.trim();
    const match = line.match(/^\[([A-Za-z0-9_.-]+)\](?:\s*#.*)?$/);
    if (match) { selected = match[1] === name; continue; }
    if (!selected || !line || line.startsWith('#')) continue;
    const field = line.match(/^([a-z][a-z0-9_]*)\s*=\s*(true|false|[0-9]+|"(?:[^"\\]|\\.)*")\s*(?:#.*)?$/);
    if (!field) throw new Error('Unsupported setting in [' + name + ']: ' + line);
    const literal = field[2];
    result[field[1]] = literal[0] === '"' ? JSON.parse(literal) :
      literal === 'true' ? true : literal === 'false' ? false : Number(literal);
  }
  return result;
}

function settings(file = path.join(root, '.github/config/targets.toml'), env = process.env) {
  const config = section(file, 'github.previews');
  const defaults = { enabled: false, provider: 'github-pages', pull_requests: true,
    branches: true, path_prefix: 'previews', state_branch: 'pages-state',
    retention_days: 14, cloudflare_project: '' };
  const all = { ...defaults, ...config };
  for (const field of ['enabled', 'pull_requests', 'branches'])
    if (typeof all[field] !== 'boolean') throw new Error('Invalid preview toggle: ' + field);
  if (!['github-pages', 'cloudflare-pages'].includes(all.provider))
    throw new Error('Unsupported preview provider: ' + all.provider);
  if (!/^[a-z][a-z0-9-]{0,30}$/.test(all.path_prefix))
    throw new Error('Invalid preview path prefix');
  if (!/^[a-z][a-z0-9-]{0,40}$/.test(all.state_branch))
    throw new Error('Invalid preview state branch');
  if (!Number.isInteger(all.retention_days) || all.retention_days < 1 || all.retention_days > 90)
    throw new Error('Preview retention must be between 1 and 90 days');
  if (all.provider === 'cloudflare-pages' &&
    !/^[a-z0-9][a-z0-9-]{0,62}$/.test(all.cloudflare_project))
    throw new Error('Configure github.previews.cloudflare_project for Cloudflare Pages');
  const repo = env.GITHUB_REPOSITORY || '';
  if (!repositoryPattern.test(repo)) throw new Error('Missing valid GitHub repository');
  const [owner, name] = repo.split('/');
  const base = name.toLowerCase() === (owner + '.github.io').toLowerCase() ? '/' : '/' + name + '/';
  return { ...all, repo, owner, name, base,
    site: 'https://' + owner.toLowerCase() + '.github.io',
    accountId: env.CLOUDFLARE_ACCOUNT_ID || '' };
}

function target(input, config) {
  if (typeof input !== 'string' || input.length < 4 || input.length > 128)
    throw new Error('Missing preview_target; specify pr:50 or branch:feature/example');
  let remove = false;
  if (input.startsWith('delete:')) { remove = true; input = input.slice(7); }
  if (input.startsWith('pr:')) {
    const value = input.slice(3);
    if (!/^[1-9][0-9]{0,8}$/.test(value)) throw new Error('Invalid PR number');
    if (!config.pull_requests) throw new Error('PR preview targets are disabled');
    return { type: 'pr', number: Number(value), alias: 'pr-' + value, remove };
  }
  if (input.startsWith('branch:')) {
    const name = input.slice(7);
    if (!safeBranch.test(name) || name.endsWith('/') || name.endsWith('.') ||
        name.includes('/.') || name.startsWith('ci/') || name === 'source')
      throw new Error('Invalid or reserved preview branch');
    if (!config.branches) throw new Error('Branch preview targets are disabled');
    const slug = name.toLowerCase().replace(/[^a-z0-9]+/g, '-').replace(/^-|-$/g, '').slice(0,30);
    const hash = crypto.createHash('sha256').update(name).digest('hex').slice(0,8);
    return { type: 'branch', name, alias: 'branch-' + slug + '-' + hash, remove };
  }
  throw new Error('Preview target must begin with pr: or branch:');
}

function sourceContext(env = process.env) {
  const defaults = env.CI_DEFAULT_BRANCH || '';
  if (env.GITHUB_ACTIONS !== 'true' || env.GITHUB_EVENT_NAME !== 'workflow_dispatch' ||
      !defaults || env.GITHUB_REF !== 'refs/heads/' + defaults ||
      env.CI_ENGINE_OPERATION !== 'preview' || env.CI_PUBLICATION_ENABLED !== 'true')
    throw new Error('Previews require explicit trusted source-branch CI dispatch');
  if (!shaPattern.test(env.GITHUB_SHA || '') ||
      !/^[1-9]\d*$/.test(env.GITHUB_RUN_ID || '') ||
      !/^[1-9]\d*$/.test(env.GITHUB_RUN_ATTEMPT || ''))
    throw new Error('Invalid trusted dispatch identity');
  const payload = JSON.parse(fs.readFileSync(env.GITHUB_EVENT_PATH, 'utf8'));
  const requested = payload?.inputs?.preview_target;
  if (typeof requested !== 'string' || !requested)
    throw new Error('Set the workflow_dispatch preview_target input');
  return { sourceSha: env.GITHUB_SHA, sourceBranch: defaults,
    runId: env.GITHUB_RUN_ID, attempt: env.GITHUB_RUN_ATTEMPT,
    target: requested };
}

async function resolveTarget(candidate, config, api) {
  if (candidate.remove) return { ...candidate, sha: null };
  if (candidate.type === 'pr') {
    const pr = await api('GET', '/repos/' + config.repo + '/pulls/' + candidate.number);
    if (pr.state !== 'open' || pr.base?.repo?.full_name !== config.repo ||
        pr.head?.repo?.full_name !== config.repo ||
        !shaPattern.test(pr.head?.sha || ''))
      throw new Error('Preview PR must be open and originate from this repository');
    return { ...candidate, sha: pr.head.sha };
  }
  const branch = await api('GET', '/repos/' + config.repo +
    '/git/ref/heads/' + candidate.name.split('/').map(encodeURIComponent).join('/'));
  if (!shaPattern.test(branch?.object?.sha || ''))
    throw new Error('Preview branch is missing a commit');
  return { ...candidate, sha: branch.object.sha };
}

module.exports = { root, section, settings, target, sourceContext, resolveTarget };
