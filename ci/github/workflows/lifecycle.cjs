'use strict';
// Immutable CI Engine compatibility entrypoint for the existing closure job.
// Fetch only the engine revision and Git blob explicitly pinned below.
const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');
const crypto = require('node:crypto');
const { spawnSync } = require('node:child_process');

const engineRevision = '8969daa7c59f240b7b70923741f17f35d271cdd1';
const engineBlob = '0e715093c5b99e13b8b34513526e2d3f346af53c';
const engineUrl = 'https://raw.githubusercontent.com/Kooraseru-Hub/CI-Engine/' +
  engineRevision + '/src/lifecycle/dispatch.cjs';

function gitBlobHash(source) {
  return crypto.createHash('sha1').update('blob ' +
    Buffer.byteLength(source, 'utf8') + '\0').update(source).digest('hex');
}

async function runLifecycle(env = process.env, request = fetch, execute = spawnSync) {
  if (env.GITHUB_ACTIONS !== 'true' || env.GITHUB_EVENT_NAME !== 'pull_request_target')
    throw new Error('Lifecycle dispatch requires a trusted PR target event');
  const response = await request(engineUrl, { signal: AbortSignal.timeout(30000) });
  if (!response.ok) throw new Error('Pinned CI Engine unavailable: HTTP ' + response.status);
  const source = await response.text();
  if (gitBlobHash(source) !== engineBlob)
    throw new Error('Pinned CI Engine lifecycle code failed Git blob verification');
  const directory = fs.mkdtempSync(path.join(os.tmpdir(), 'ci-engine-lifecycle-'));
  try {
    const runner = path.join(directory, 'dispatch.cjs');
    fs.writeFileSync(runner, source, { mode: 0o600 });
    const result = execute(process.execPath, [runner], {
      cwd: path.resolve(__dirname, '../../..'), env, stdio: 'inherit',
      shell: false, timeout: 900000,
    });
    if (result.error || result.status !== 0) {
      throw new Error('CI Engine lifecycle failed: ' +
        (result.error?.message || result.status));
    }
  } finally {
    fs.rmSync(directory, { recursive: true, force: true });
  }
}

module.exports = { engineRevision, engineBlob, engineUrl, gitBlobHash, runLifecycle };
