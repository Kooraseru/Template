# GitHub configuration and optional job visualization

`repo/config/github.toml` owns repository paths, project aliases, output-branch
declarations, optional branch bootstrap, and credential-name mappings.
`repo/ci/github/` adapts the existing scheduler's validated tasks to GitHub Actions.
The maintained workflow only checks out the repository and starts Luau.

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

The entrypoint passes the run's available secrets and variables as JSON. Luau
lists the available names and logs each configured role/name/availability, never values.
This includes organization secrets and variables only when GitHub makes them
available to this repository and run. It does not enumerate inaccessible account
secrets. The complete JSON inventory is removed from the environment before
component processes start. Generated execution jobs do not receive that inventory.

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

Run branches are retained for inspection. No credentials are embedded in the
generated YAML or commits. The ordinary checkout token stays read-only. Existing
privileged-component planning restrictions remain in force.

Generated YAML saved under `build/github/` is not executable by itself. Without a
permitted push and a repository ref, GitHub cannot turn it into native jobs. No
workflow is generated, committed, or pushed on the missing-credential path.

## Other configuration owners

- `repo/content/releases/packages.toml` declares files distributed as release packages.
- `repo/content/releases/releases.toml` declares release records and their commit/tag data.
- `repo/ci/dependencies/` owns CI tool setup. Lune's installer and pinned checksums live
  together under `repo/ci/dependencies/lune/`; Pages requests Pandoc when rendering.
- `source/` contains the application source and its host implementations.
