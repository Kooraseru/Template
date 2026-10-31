# GitHub configuration and optional job visualization

`repo/config/github.toml` owns repository paths, project aliases, output-branch
declarations, optional branch bootstrap, and credential-name mappings.
`repo/ci/github/` adapts the existing scheduler's validated tasks to GitHub Actions.
The maintained workflow checks out the repository, starts Luau, and carries a small native Pages adapter. Luau decides whether and what to deploy.

## Repository paths and aliases

Set `github.repository` to the repository running this CI, as `owner/repository`.
When consuming this template, replace the template repository path with yours.

Aliases are names you explicitly fill in. There are no reserved `repo` or `org`
aliases and no `@` syntax. For example:

```toml
[github.aliases]
public_repo = "your-account/your-public-repository"
shared_tools = "your-organization/shared-tools"
organization = "your-organization"
```

An operation that sends files to a public repository can resolve `public_repo`
instead of embedding its destination in code. Defining an alias does not publish
anything or grant access. Bootstrap runs its graph in the current repository;
cross-repository publishing is a separate operation using those destinations.

## Credential names, never credential values

**Never put a token, password, or private key in TOML, scripts, or committed files.**
Store real credentials in GitHub Settings → Secrets and variables → Actions.
Only put their **names** in configuration:

```toml
[github.credentials]
app_id = "MY_APP_ID_VARIABLE"
app_private_key = "MY_APP_PRIVATE_KEY_SECRET"
bootstrap_token = "MY_BOOTSTRAP_TOKEN_SECRET"
release_token = "MY_RELEASE_TOKEN_SECRET"
```

Here `MY_BOOTSTRAP_TOKEN_SECRET` is the name of a GitHub secret, not a token.
Role names describe capabilities; values identify the secrets or variables
holding the actual data. Other names can be configured without editing scripts.
The App ID may be a variable or a secret. Private keys and tokens must be secrets.
Only the roles actually used by an operation are consumed; listing `release_token`
does not enable release publishing.

The first Luau invocation exports configured credential names as step outputs.
GitHub then looks up only the App ID, private key, and bootstrap token selected by
those outputs. The next Luau invocation logs selected names and availability,
never values. It clears their transport environment variables before component
processes start. It does not receive a snapshot of all GitHub secrets or variables.
Organization credentials are available only when GitHub grants this repository
access to them. Other configured roles are listed as not requested by bootstrap.
Enumerating every repository secret would require secret-administration access;
bootstrap does not request that permission. Generated execution jobs receive no
bootstrap credentials.

## Automatic selection and fallback

On a push to `source`, bootstrap validates the discovered task graph first.
When `github.bootstrap.enabled` is true, it tries these credentials in order:

1. The configured `app_id` and `app_private_key`. Install the App on this repository
   with **Contents: write** and **Workflows: write**. Luau signs an App JWT using
   OpenSSL on the Linux runner and requests a short-lived installation token
   restricted to this repository and those permissions. Private-key data is passed
   through stdin, not written to files. The token is revoked after the push.
2. The configured `bootstrap_token` secret, if present. It must be permitted to
   push branches and workflow files to this repository. For a classic PAT this
   includes `workflow` and the relevant repository scope; fine-grained credentials
   need Contents and Workflows write access. Repository rules still apply.

GitHub's automatic `GITHUB_TOKEN` cannot trigger another push workflow and is not
accepted as the configured branch-bootstrap credential. Merely finding a secret
does not prove it has the required permissions; GitHub verifies access when used.

If credentials are absent, unavailable, invalid, or rejected, bootstrap logs the
configured App/token names and continues through the original Luau scheduler in
the current job. Setting `github.bootstrap.enabled = false` uses that scheduler
directly. Components still have named log groups and timestamped outcomes.

## What a successful branch launch does

The adapter creates a detached temporary worktree from the exact source commit,
generates `.github/workflows/ci-execution.yml`, and pushes a new branch named from
`github.bootstrap.branch_prefix`, the initiating run ID, and its attempt number.
This is an explicit generated commit on a new branch; it does not update `source`.
The App/token push starts a separate **CI Execution** run. Bootstrap then finishes
and links to that run. The starting run's success means handoff succeeded; execution
success/failure belongs to the linked run.

Jobs and `needs` edges come directly from the scheduler's discovered tasks. No
component inventory or predefined phases are maintained in YAML. Each job checks
out the exact original source SHA and invokes the same component invoker and
output checks. Declared outputs move between dependency jobs as validated tar
artifacts, preserving repository-relative paths. GitHub displays job progress,
timings, dependency failures, and logs. A final job reports the component outcomes.

An always-run final cleanup job deletes its own temporary branch using GitHub's
automatic token. It has Contents write access. Generation jobs remain read-only; publication jobs receive the permissions required by their boundary and native adapter.
Cleanup checks the repository, namespace, current workflow ref, default branch,
and original branch-head SHA before deleting anything. A branch that moved after
the run started is left untouched. GitHub retains the run results and logs after
branch deletion. Force-cancelling a workflow or a runner startup failure can
prevent its cleanup job from executing. No credentials are embedded in generated
YAML or commits. Privileged components are restricted to push events and publication verifies the configured repository and trusted run ref.

Generated YAML saved under `build/github/` is not executable by itself. Without a
permitted push and a repository ref, GitHub cannot turn it into native jobs. No
workflow is generated, committed, or pushed on the missing-credential path.

## Other configuration owners

- `repo/content/packages/packages.toml` declares libraries/packages intended for GitHub Packages, independently from Releases.
- `repo/content/releases/releases.toml` declares release records and their commit/tag data.
- `repo/ci/dependencies/` owns CI tool setup. Lune's installer and pinned checksums live
  together under `repo/ci/dependencies/lune/`; Pages requests Pandoc when rendering.
- `source/` contains the application source and its host implementations.

## Publication

Publication is separate from generation. Discovered `publish-*` components declare
capability dependencies in their own manifests. They use the run-provided
`GITHUB_TOKEN`; no personal credential or App is required for same-repository
publication. Write access remains subject to repository and environment policies.
Read-only component child processes do not receive `GH_TOKEN`.

Set these **Actions variables** in GitHub Settings > Secrets and variables > Actions:

| Variable | Behavior |
| --- | --- |
| `CI_PUBLISH_RELEASES=false` | Disable publishing records from `repo/content/releases/releases.toml`. Existing tags/releases follow `release.on_existing` (default `replace`). |
| `CI_PUBLISH_BRANCHES=false` | Disable pushing generated branches from `repo/config/github.toml`, preserving output-branch history. The default source branch cannot be overwritten. |
| `CI_PUBLISH_PACKAGES=false` | Disable configured GitHub Packages publication. A real registry-format adapter is required; none is currently installed. |
| `CI_PUBLISH_PAGES=false` | Disable Pages deployment. Otherwise deploy only when Pages is enabled with GitHub Actions as its source. |

Enabled component manifests and their content declarations drive automatic publication.
Unset GitHub variables do not disable it; an explicit false is an optional override. Pages follows the repository's existing Pages setting. Sample
package records without a format, version, and repository only test compilation/staging.
They are never attached to Releases or converted into registry packages.

Pages uses GitHub's native upload/deployment actions because these are runner
integration steps. The minimal entrypoint carries the fallback adapter. Generated
execution jobs read the equivalent component-owned `github.toml` adapter from
`publish-pages/`. Deployment waits for the site and compilation dependencies.
Environment protection rules are honored, never changed automatically.

Package configuration lives in `repo/content/packages/`, separate from Releases.
See its README and `records/*/package.toml` folders. `packages.toml` owns only shared policy, including `packages.on_existing` (default `replace`). Registry integrations belong with publishing, never
with the compiler or the generic staging provider. A configured but unavailable
adapter fails explicitly rather than claiming that a package was published.


## Contribution templates and labels

- `ISSUE_TEMPLATE/*.yml`: bug, feature, and question forms discovered by GitHub.
- `ISSUE_TEMPLATE/config.yml`: disables blank issues for ordinary contributors.
- `pull_request_template.md`: default PR description; authors can edit it.
- `repo/config/labels.toml`: names, colors, and descriptions managed by the Luau CI pipeline.

Templates are authored directly in `.github/` on the default `source` branch; label configuration lives in `repo/config/`. They are not
generated copies of templates stored elsewhere. Issue forms require appropriate
fields, but templates are not a universal barrier against off-format submissions.

GitHub reads the templates natively. It does **not** read `repo/config/labels.toml` natively:
`repo/ci/components/sync-labels/` discovers and validates those definitions and
creates or updates labels on trusted source pushes using the run-provided token
with `issues: write`. There are no supplied tokens, extra workflows, or external
sync services. An already matching catalog reports skipped.

Label synchronization preserves IDs and issue associations for labels that remain declared. It removes every unlisted repository label, including GitHub defaults and labels created by other automation. Deleted labels are detached from existing issues/PRs. Forms must reference labels declared in `repo/config/labels.toml`.
Change a label definition in that configuration file; do not maintain another list in CI code.

To disable synchronization, set its component manifest's `enabled` to false.
Labels then need to be created through GitHub settings or its API before forms
can apply them. Org-level default labels apply to new repositories rather than
continually updating existing ones.

Labels classify issues/PRs. Git tags identify commits/releases and are separate.

## Workflow lockfiles and artifact attestations

`.github/workflows/actions.lock` is generated by GitHub's official
`gh actions-lock` CLI, not hand-authored configuration. The tool version is pinned
in `repo/ci/dependencies/actions-lock/config.toml`. Run `gh actions-lock --no-narrow`
after changing native `uses` bindings, and review the diff. Do not use
`--accept-moved` automatically. Generated execution workflows are locked before
being pushed; failure falls back to the existing verified entrypoint rather than
pushing an unlocked execution workflow.

`repo/config/attestations.toml` selects best_effort or disabled. The prepare stage
collects and hash-checks the actual release assets. The native adapter uses
GitHub's official attest action with a SLSA v1 predicate identifying the exact
checked-out source SHA separately from the generated workflow SHA. This does not
claim SLSA Level 3 or reproducible builds.

Signing is best-effort, not a release gate: unsupported plans/permissions or
signing outages produce a warning and a failed (non-blocking) feature outcome,
while unrelated work continues. Private repos are attempted because Enterprise
Cloud supports private attestations; failures are not redirected to a public
signing service. A disabled/unprepared feature is skipped, never passed. A
successful attestation is verified independently against the published binary.

The fallback entrypoint carries the native signing bridge; generated jobs use
the component-owned adapter. No additional maintained workflow is introduced.
See the [stage graph design](stage-graph-design.md) for the proposed finer-grained execution graph.
