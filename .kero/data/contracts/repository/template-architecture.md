# Repository template architecture

Each contract owns its subject. Other documents must not restate or override it:

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

`.github/workflows/ci.yml` is the single workflow. It owns events, job dependencies,
matrices, runners, permissions, artifact transfers, and stage selection. Reusable
actions and implementation modules perform individual operations, not independent
pipeline orchestration. Separate permission boundaries use separate jobs.

Authorized hosted source execution may publish completed outputs after its gates
succeed. Manual inputs request operations; they cannot grant permissions.
Generation and publication consume the same artifacts, without a separate
privileged rebuild.

## Directory and build ownership

- `.github/actions/`: reusable workflow operations.
- `.github/integration/`: GitHub-specific controls, requests, and adapters.
- `config/`: repository publication settings and infrastructure tool configuration.
- `libraries/bootstrap/`: shared utilities and native primitives.
- `libraries/registry/`: development catalogues and configuration, not an application runtime registry.
- `libraries/testing/`: typed metatable tests, comparisons, execution, and reporting.
- `validation/`: repository, compatibility, contract, and policy checks.
- `fabricator/`: generic target execution, environments, toolchains, and packaging mechanisms.
- `security/`: authorization and trusted evidence.
- `publication/`: repository, documentation, and release publication implementations.
- `src/`: application implementation, contracts, dependencies, assets, and build declarations.
- `build/`: disposable, Git-ignored output.

`src/build.toml` owns application targets, compiler requirements, environment
selection, commands, and package contents. Native manifests and lockfiles own
application dependencies. `config/project.toml` owns repository output controls.
Source declarations cannot grant signing or publication authority. Historical
source snapshots retain their original configuration layout.

No extra top-level source directories, mandatory empty language folders, or
boilerplate manifests for ordinary modules. Existing hidden editor metadata and
tracked `.kero` guidance remain tooling. Development guidance belongs in `.kero/data/`.

## Implementation boundaries

The template is language-agnostic. Toolchains are optional; preserve native tool
configuration formats. Project-managed Node is excluded. Luau owns controller
behavior, with native helpers for operations requiring exact external semantics.

Tests bind typed cases to their actual function under test through the shared
library. Do not require a separate case manifest for each ordinary module.

Plugin and Workshop contracts are independent and versionless. Workshop is
data-only and cannot register execution providers. Applications implement runtime
permissions, isolation, format inspection, and recovery; CI cannot establish those
guarantees from metadata.

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
