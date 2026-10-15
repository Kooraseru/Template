import { readRequest } from './request.mjs';

// Completed evidence from this run may feed its own publication jobs. Other
// consumers still require the originating workflow to have completed successfully.
export function pendingReceiptAllowed(run, env = process.env) {
  return env.CI_PUBLICATION_JOB === 'true' && env.ACT !== 'true' && env.GITHUB_ACTIONS === 'true'
    && env.GITHUB_SERVER_URL === 'https://github.com' && ['workflow_dispatch', 'push'].includes(env.GITHUB_EVENT_NAME)
    && env.GITHUB_REF === 'refs/heads/source' && ['Publish', 'Full Run'].includes(readRequest(env).operation)
    && String(run.id) === env.GITHUB_RUN_ID && run.status === 'in_progress' && run.conclusion == null
    && run.head_sha === env.GITHUB_SHA && run.actor.login === env.GITHUB_ACTOR;
}
