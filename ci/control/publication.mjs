import { actor, isAdmin } from '../receipts/github.mjs';
import { readRequest, parsePR } from './request.mjs';

export function authorizePublication(env = process.env, administrator = isAdmin) {
  if (env.ACT === 'true' || env.GITHUB_ACTIONS !== 'true' || env.GITHUB_SERVER_URL !== 'https://github.com'
      || env.GITHUB_REF !== 'refs/heads/source') throw Error('Local or untrusted publication denied; hosted source execution is required');
  if (env.GITHUB_EVENT_NAME === 'push') return true;
  const controls = readRequest(env);
  if (env.GITHUB_EVENT_NAME !== 'workflow_dispatch' || parsePR(controls.pull_request)
      || !['Publish', 'Full Run'].includes(controls.operation) || !administrator(env.GITHUB_ACTOR || actor())) {
    throw Error('Manual publication requires a repository administrator and Publish or Full Run on Source');
  }
  return true;
}
