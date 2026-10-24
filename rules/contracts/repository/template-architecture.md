# Repository template architecture

Each contract owns its subject. Other documents must not restate or override it:

- [Source updates](source-updates.md): development authority, post-push validation, and downstream eligibility.
- [Local testing](local-testing.md): local execution, PR comparison, platform coverage, and log access.
- [Build receipts](build-receipts.md): execution approval, evidence identity, signing, acceptance, and reuse.
- [Releases](releases.md): public versions, release assets, replacement, and release notes.

Keep operational settings in their implementation-owned configuration files;
contracts describe boundaries rather than duplicate configurable values. Run logs,
failure histories, and machine-specific installation paths do not belong here.

## Repository and workflow

`source` is the authored default branch and PR target. `main` is generated from
source after authorization. Do not introduce another repository or require
organization-specific infrastructure.

`.github/workflows/ci.yml` is the single build and publication orchestrator. It owns events, job dependencies,
matrices, runners, permissions, artifact transfers, and stage selection. Reusable
actions and implementation modules perform individual operations, not independent
pipeline orchestration. Separate permission boundaries use separate jobs.
Independent maintenance workflows may exist without participating in CI gates.
Template conformance is owned by [the conformance contract](template-conformance.md).


## Directory and build ownership

- `.github/workflows/ci.yml`: GitHub job orchestration; `.github/actions/` contains environment setup
- `ci/run.sh` → `ci/main.luau`: sole public CI command interface and explicit operation dispatcher
- `ci/integration/`: GitHub-specific controls and editor adapters
- `ci/libraries/`: shared utilities, registry, testing, and Node built-in native-compatible primitives
- `ci/validation/`: conformance, contracts, and policy checks
- `ci/fabricator/`: optional build targets, toolchains, images, and packages
- `ci/security/`: publication authorization and signed receipts
- `ci/publication/`: generated repository, Pages, and releases
- `config/`: repository and developer-tool configuration
- `rules/`: tracked Markdown guidance; ignored `AGENTS.md` is generated locally
- `source/`: optional application implementation and `build.toml`
- `build/`: disposable Git-ignored output and local bridge state

`source/build.toml` controls application compilation, selected environments, and package paths. A Rust consumer places its entire optional Cargo manifest/lockfile/config under `source/cargo/`. The fabricator uses explicit paths. `config/project.toml` controls publication. Source declarations cannot grant signing or publishing authority.

No mandatory language folder, compiler smoke project, root Cargo manifest, PowerShell entry points, or second AI rule runtime.

## Implementation boundaries

The tracked act defaults live at `config/docker/actrc`; `bash ci/run.sh configure-editor` copies them to an ignored root `.actrc` because act only auto-discovers that conventional path.

The template is language-agnostic. Toolchains are optional; preserve native tool
configuration formats. Luau owns controller behavior. A small package-free Node helper provides ECMAScript-compatible number formatting and Ed25519 operations without Cargo; Node is a CI runtime dependency, not a mandated application language.

Tests bind typed cases to their actual function under test through the shared
library. Do not require a separate case manifest for each ordinary module.

Application extension boundaries belong to [the extension contract](../extensions.md).

Use explicit artifact transfers between isolated jobs. Keep build-environment
creation free of circular dependencies on the image being created.

## Repository credentials and protection

No hardcoded credentials, mandatory PATs, inherited project secrets, or required
GitHub Apps. Repository publication uses the automatic `GITHUB_TOKEN` with narrowly
scoped job permissions. Build and validation jobs remain read-only; trusted jobs
receive only the additional permissions required by their operation.

Branch protection, token permissions, and environment restrictions remain
authoritative. Consuming repositories configure source PR/check protection and
admin-only merge/update or bypass permissions. Approval cannot expand token
permissions or silently bypass protection. Never execute untrusted PR code on
privileged self-hosted runners.
