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

`.github/actions/` contains reusable actions for individual operations. `ci/` contains their implementation scripts. Neither is a second orchestrator.

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

Release channels are governed by `ci/releases/channels.toml` and the [release contract](releases.md). Canary follows the newest verified source commit; stable and beta select explicit commits. Existing channel releases and tags move on promotion.

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

Scripts inside `ci/` implement individual operations invoked by workflow jobs.

Local `act` execution is artifact-only and must not publish remotely.

We recognize that `act` uses Docker and cannot reproduce native macOS or Windows runner behavior. Native platform jobs are verified on their appropriate GitHub runners. This is a documented limitation, not a reason to create another workflow architecture.

## 6. Directory ownership

Keep these boundaries:

- `.github/workflows/ci.yml` — all workflow orchestration.
- `.github/actions/` — reusable action implementations.
- `ci/images/` — Dockerfiles and CI container image definitions, not runner wrappers.
- `ci/validation/` — repository and configuration validation.
- `ci/build/` — build/test execution helpers.
- `ci/distribution/` — distributable packaging.
- `ci/releases/` — release generation and publication implementations.
- `ci/repo/` — generated `main` branch contents and publication.
- `ci/pages/` — website generation and deployment.
- `ci/lib/` — genuinely shared implementation utilities.
- `src/` — actual project source, organized by subsystem.
- `tests/` — cross-subsystem, integration, compatibility, and end-to-end tests.
- `build/` — all disposable/generated output; Git-ignored.
- `.kero/` — development-tool configuration and state.
- `.kero/data/` — repository contracts, knowledge, decisions, and other tool data; do not place these beside `config`.

Subsystem-local tests may live alongside their implementations under `src/`.

Do not move source into language-specific top-level folders.

Do not create placeholder files merely to fill the proposed tree.

## 7. Language and toolchain support

The template should support projects using combinations of:

- Luau and Lune
- C/C++, CMake, Clang, GCC
- Rust and Cargo
- Additional toolchains where necessary

Toolchains are optional capabilities, not universal requirements.

Preserve conventional configuration files where tools expect them, including `.luaurc`, `CMakeLists.txt`, `CMakePresets.json`, `.clangd`, `.clang-format`, `.cargo/config.toml`, and `rust-toolchain.toml` when applicable.

Use platform-appropriate build matrices. Linux jobs may use custom Docker images from `ci/images/`; native Windows and macOS jobs use suitable runners.

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

Define validation rules and test cases in declarative data files such as JSON
or TOML. Luau executes reusable check operations; it does not hardcode individual
rules, expected results, or case definitions.

If a particular operation requires different permissions, use separate **jobs within `ci.yml`**, not another workflow.

If a technical limitation prevents the requested behavior, identify the exact limitation and propose the smallest necessary exception.

**Implementation is authorized. Preserve these agreed boundaries while adapting the imported material.**

Unless you find an actual technical blocker, consider these architectural questions settled.
