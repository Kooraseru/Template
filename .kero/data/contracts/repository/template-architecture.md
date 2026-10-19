# Repository Template Architecture — Decisions and Constraints

Treat the following as the agreed architecture. Do not reopen these decisions unless there is a concrete technical incompatibility with GitHub Actions, `act`, or the existing project.

## 1. Repository branches

- **`source`** is the default development branch. It contains the actual source code, CI implementation, tooling, contracts, and templates.
- **`main`** is a generated publication branch, built entirely from `source`.
- Pull requests target `source`.
- CI must not modify `source` or publish to `main` during pull-request validation.
- A successful, authorized push to `source` may regenerate and update `main`.
- Do not introduce another repository or require organization-specific infrastructure.

We understand that GitHub displays the default `source` branch in its code view. That is acceptable.

## 2. One GitHub Actions workflow

There is **one workflow file: `.github/workflows/ci.yml`**.

It owns all GitHub Actions orchestration:

- Event triggers and execution context
- Job dependencies and matrices
- Runner and container selection
- Job permissions and environments
- Build/test/generation execution
- Artifact transfers
- Conditional publication

Do not create separate `build.yml`, `release.yml`, `pages.yml`, `publish.yml`, or other workflow files.

Use multiple jobs inside `ci.yml`, including parallel jobs where appropriate.

`.github/actions/` contains reusable actions for individual operations. Implementation belongs to the ownership directories below. Neither is a second orchestrator.

## 3. Execution behavior

The same CI workflow supports different access contexts.

**Pull request:**
- Validate, build, test, package, and generate all applicable outputs.
- Generate prospective `main` contents, Pages output, release packages, and container images when enabled.
- Make applicable outputs available as inspectable CI artifacts.
- Do not publish, deploy, sign, push branches, or access privileged credentials.

**Trusted push to `source`:**
- Run the same validation and generation stages.
- After required checks succeed, publish eligible outputs to their respective destinations.
- Update generated `main`, deploy Pages, publish configured releases, and transfer CI images as workflow artifacts.

**Manual execution:**
- Allow validation and artifact generation.
- Do not grant publication privileges merely because an input requests publication. Trusted GitHub context and repository authorization must still permit it.

Public versions are selected explicitly in `publication/releases/versions.toml` under the [release contract](releases.md). Release uses stable SemVer; Pre-Release uses `-pre.N`. Published versions support replacement of their selected content and source tag. Promotion creates a new version while preserving the prerelease. Internal validation staging remains separate.

The central principle is:

**Generation is common to all eligible executions. Publication is a separate, authorized consequence of generation.**

## 4. Credentials and security

This is a reusable repository template.

It must contain:
- No hardcoded secrets or tokens.
- No organization-specific GitHub App dependencies.
- No mandatory personal access tokens.
- No inherited project-specific signing or publication credentials.

Use GitHub's automatically supplied `GITHUB_TOKEN` with narrowly scoped job permissions wherever supported.

Keep ordinary validation/build/generation jobs read-only. Publication jobs receive only the necessary write permissions.

Optional signing or external publication must be explicitly configured by the consuming repository. Signing happens only in a trusted stage.

GitHub branch protection, environment restrictions, and token permissions remain authoritative. Configuration files and CI scripts cannot grant permissions.

Publication must use the current repository's automatically supplied `GITHUB_TOKEN`, without a PAT or stored publication secrets. Source PR/check protection and admin-only PR merging must be configured in each consuming repository. Publication environments are optional. If branch rules prevent an update, use the repository's review process or document the required setting; approval cannot expand token permissions. Do not silently bypass protection.

Never execute untrusted PR code on privileged self-hosted runners.

## 5. Local execution

**`act` is the designated local CI execution mechanism.**

The GitHub Local Actions VS Code extension is already being used for this.

Local execution must invoke the same `.github/workflows/ci.yml` as hosted GitHub Actions.

Do not create `ci/pipeline.luau` or another local CI orchestrator.

Implementation modules perform individual operations invoked by workflow jobs.

Local `act` execution is artifact-only and must not publish remotely.

We recognize that `act` uses Docker and cannot reproduce native macOS or Windows runner behavior. Native platform jobs are verified on their appropriate GitHub runners. This is a documented limitation, not a reason to create another workflow architecture.

## 6. Directory ownership

The modular template owns these source boundaries:

- `.github/workflows/ci.yml`: the single hosted/local workflow.
- `.github/actions/`: reusable hosted actions.
- `.github/integration/`: GitHub-specific requests, controls, approvals, and adapters.
- `config/`: project configuration and native tool settings.
- `libraries/bootstrap/`: shared development infrastructure and native primitives.
- `libraries/registry/`: development catalogues and configuration, not an application runtime registry.
- `libraries/testing/`: shared typed metatable tests, execution, comparisons, and reporting.
- `validation/`: repository, compatibility, declared-contract, and policy checks.
- `fabricator/`: source target execution and packaging; images and toolchains live under `distribution/`.
- `security/access/` and `security/receipts/`: separate authorization and evidence boundaries.
- `publication/releases/`, `publication/repo/`, and `publication/pages/`: completed publication outputs.
- `src/`: application-defined APIs, optional language implementation folders, plugins, Workshop content, and assets.
- `build/`: disposable output; Git-ignored.

No extra top-level source directories, mandatory empty language folders, or
boilerplate manifests for ordinary modules. Existing hidden editor/tool metadata
and the explicitly tracked `.kero` guidance remain repository tooling.
`fabricator/workflow.luau` implements a build stage, not a second job orchestrator.

Plugin and Workshop contracts are independent and versionless. Workshop is
data-only and cannot register execution providers. Applications enforce actual
capabilities, permission authorization, isolation, format inspection, and lifecycle
rollback; CI metadata does not establish those runtime guarantees.

## 7. Language and toolchain support

The template should support projects using combinations of:

- Luau and Lune
- C/C++, CMake, Clang, GCC
- Rust and Cargo
- Additional toolchains where necessary

Toolchains are optional capabilities, not universal requirements.

Preserve conventional configuration files where tools expect them, including `.luaurc`, `CMakeLists.txt`, `CMakePresets.json`, `.clangd`, `.clang-format`, `.cargo/config.toml`, and `rust-toolchain.toml` when applicable.

Use platform-appropriate build matrices. Linux jobs may use custom Docker images from `fabricator/distribution/images/`; native Windows and macOS jobs use suitable runners.

Avoid circular dependencies where a CI image must already exist to build that same image.

## 8. Generic template content

The template must be usable by unrelated projects without inherited project
identity, organization requirements, or application-specific behavior.

Preserve intended tooling integrations and their existing configuration formats.

Replace project-specific references, contracts, organization names, publication channels, and release assumptions with generic definitions or configurable examples.

Development-tool data belongs under `.kero/data/`.

## 9. Artifact handling

Generated outputs belong under `build/`.

Because GitHub Actions jobs have isolated filesystems, use explicit artifact upload/download steps when outputs need to pass between jobs.

PR and trusted-source executions should share the same generation logic. Do not rebuild publication artifacts using a separate, privileged implementation.

Privileged signing may transform an already validated unsigned artifact, followed by any necessary verification.

## 10. Implementation expectations

Treat the full proposed tree as an architectural target, not an instruction to immediately create every file.

Prefer the smallest implementation that satisfies these boundaries.

Operational policy and catalogues may use JSON or TOML. Tests declare typed cases
and bind their function under test through the shared Luau metatable testing
library. Do not require separate test/cases/ruleset files per ordinary module.
Project-managed Node must be removed as migration completes; retain frozen
canonical-byte compatibility and publication authorization during that work.

If a particular operation requires different permissions, use separate **jobs within `ci.yml`**, not another workflow.

If a technical limitation prevents the requested behavior, identify the exact limitation and propose the smallest necessary exception.

**Implementation is authorized. Preserve these agreed boundaries while adapting the imported material.**

Unless you find an actual technical blocker, consider these architectural questions settled.
