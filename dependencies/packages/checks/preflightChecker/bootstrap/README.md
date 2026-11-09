# External publication checks

From the Template root, install the workspace dependencies and build the pilot image.

```text
node dependencies/packages/core/dependencyLoader/index.ts
docker build -f dependencies/packages/checks/preflightChecker/bootstrap/rehearsal.Dockerfile -t template-preflight:local .
node build/dependencies/npm/node_modules/preflight/bin/preflight.js rehearse --provider dependencies/packages/checks/preflightChecker/bootstrap/provider.cjs --environment dependencies/packages/checks/preflightChecker/bootstrap/environment.cjs --profile dependencies/packages/checks/preflightChecker/bootstrap/profile.json --entry push --target work/labels/sync --json
```

Use `governance/branches/publish` as the target to rehearse publishing generated content to a local bare repository. The branch rehearsal reports source compilation as skipped because it requires Docker builds. It still exercises branch generation and publication, which use separate artifacts. A successful branch publisher outcome therefore accompanies an incomplete overall rehearsal.

The profile defaults to `create`. To exercise other cases, pass a profile with the same image and a different scenario. Labels support `active`, `archived`, `malformed`, and `http-error`. Branches support `update` and `reject`. The rejection scenarios intentionally produce a failed task.

The mock implements the subset of the GitHub REST contract used by the pilot. It runs inside the same container as the tasks and rejects unmatched operations. The rehearsal uses current tracked source files, dummy credentials, and Docker's isolated loopback network. It records the operations exercised and leaves live write acceptance unverified.

Dispatch **CI Start Workflow** with mode **remote-read** from GitHub Actions to inspect configured labels and destination branches. The workflow issues only allowlisted REST reads. Missing or inaccessible state remains unverified. An archived configured label or an attempted publication to the default branch fails the check.
