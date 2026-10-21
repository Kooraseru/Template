# Repository template contributor source

This is the development tree for a reusable repository template. Development and
pull requests belong on `source`; `main` contains generated publication output.
The template does not assume a particular application, organization, or language.

For the agreed boundaries and publication rules, read
[the template architecture](rules/contracts/repository/template-architecture.md).

## Running CI locally

Run `bash ci/run.sh validate` for repository checks or `bash ci/run.sh rules sync` to regenerate ignored `AGENTS.md`. The public CI interface is `ci/run.sh` -> `ci/main.luau`; the GitHub workflow invokes that interface from independent permission-scoped jobs.


Use [GitHub Local Actions for VS Code](https://marketplace.visualstudio.com/items?itemName=SanjulaGanepola.github-local-actions)
to run `.github/workflows/ci.yml` locally through `act`. Install `act` and Docker
for container jobs, open this repository in VS Code, and select **CI** in the
extension's Workflows view. Configure event payloads, runners, inputs, and artifact
options through the extension as needed.

The same workflow defines local and hosted CI. Its operations belong to the
infrastructure directories below. `ci/fabricator/workflow.luau` executes a selected
build stage; `.github/workflows/ci.yml` owns job orchestration.
Local runs are artifact-only. They must not publish remotely.
Native platform jobs still require verification on their appropriate GitHub
runners; sharing a workflow does not guarantee identical host environments.

## Hosted administrator controls

Open Actions, select CI, and choose Run workflow. The twelve dropdowns select
operations, PRs, validation suites, build targets, output generation, cache behavior
and gate overrides. Two optional paired inputs select a SemVer version and source SHA. See [the CI control panel](ci/integration/README.md) for details.

## Repository responsibilities

- `.github/workflows/ci.yml`: triggers, jobs, dependencies, permissions, and publication gates.
- `.github/actions/`: reusable environment setup steps.
- `ci/integration/`: GitHub requests, manual controls, approvals, and stage adapters.
- `config/`: project configuration and tool settings.
- `ci/libraries/`: reusable bootstrap utilities, development registry, and typed testing.
- `ci/validation/`: repository, policy, and declared-contract validation.
- `ci/fabricator/`: target execution, images, toolchains, and distribution packaging.
- `ci/security/`: publication access and trusted build receipts.
- `ci/publication/`: release, generated repository, and documentation outputs.
- `src/`: application-defined APIs, implementation, plugins, Workshop content, and assets when used.
- `.kero/`: development-tool configuration and state.
- `rules/`: repository contracts, knowledge, and decisions.
- `build/`: disposable generated output, ignored by Git.

Toolchains are optional capabilities. A consumer enables the toolchains and
outputs its project actually uses. Pull requests generate inspectable outputs
without publication privileges. Authorized pushes to `source` may publish those
validated artifacts after all required checks pass.

## Declarative checks

Policies and operational catalogues use JSON or TOML. The shared
[testing library](ci/libraries/testing/README.md) supplies typed Luau declarations,
execution, comparisons, and reporting. See [validation](ci/validation/README.md).

## Configuring a consuming repository

Set its default branch to `source` and target pull requests there.
Edit `config/project.toml` for repository, documentation, and release publication.
Edit `src/build.toml` for application targets, toolchains, environments, packaging,
and build/test commands. Dependencies and lockfiles stay beside native source manifests. Commands are argument arrays; use an explicit shell invocation when
a command needs shell syntax. Place all build output under `build/`.
Rust and CMake require explicit versions when enabled.

The catalogue offers 24 Linux images and 32 compiler profiles; they are opt-in. Edit
`build.targets` to select named entries from `ci/fabricator/targets.json`, and select
their required images through `images.names`. The validation job checks those
references before building. See [the image catalogue](ci/fabricator/distribution/images/README.md) for
distributions and profiles. Windows and macOS each have x86_64 and ARM64 targets.

Each target compiles a small toolchain fixture before running project commands.
Native targets execute it; MinGW targets compile a Windows executable from Linux.
Container targets build within their selected image. Native targets use their
specified Windows or macOS runner. Commands receive `CI_BUILD_TARGET` and
`CI_TARGET_TRIPLE`; container profiles also provide compiler settings. MinGW's
CMake toolchain file is available through `CMAKE_TOOLCHAIN_FILE`.

Use `build.matrix` for explicit custom entries; a nonempty matrix overrides
`build.targets`. If both lists are empty, `build.runner` supplies a single entry
named `default`. Distribution artifacts and logs are separated by target name;
release assembly verifies every selected distribution.

Application source targets use separate `[[targets]]` entries with explicit `id`,
`system`, and `path` fields. Cargo and CMake own compilation. Omit `build.projects`
to build all declared targets, or select their identifiers explicitly. A repository
with no application targets needs no language folders. See [project configuration](config/README.md).

Edit publication templates under `ci/publication/repo/templates/`. Select commit-based
explicit public versions and full source SHAs in `ci/publication/releases/versions.toml`;
the initial empty list publishes no public version. See
[versioned releases and source protection](ci/publication/releases/README.md).
Image Dockerfiles belong under `ci/fabricator/distribution/images/`, with image choices in its catalogue.
Pages uses Markdown templates under `ci/publication/pages/templates/`.

Publication uses the current repository's automatically supplied `GITHUB_TOKEN`;
no PAT, signing key, organization app, or stored secret is required.
For Pages, enable GitHub Actions as the Pages source. Its `github-pages`
deployment environment is created in the consuming repository when used.
Repository branch rules and token permissions
remain authoritative: publication will fail rather than bypass protection.
Allow the workflow's token to update `main` if generated-branch publication
is desired. Signing and external destinations require consumer-specific trusted
jobs; this template supplies no signing credentials.

Source PR/check rules and admin-only merging are required for official
publication; import both release protection rulesets in each consuming repo.
Additional publication approval requirements are optional repository settings. Maintainers may add an
environment with required reviewers to a publication job to pause it for approval
in GitHub. Templates do not transfer those reviewer settings. Approval permits a
job to start; it cannot increase token scopes or override branch protections.
If branch rules require a reviewed change to `main`, use a publication pull
request and merge it through GitHub rather than providing broader credentials.

Local artifact storage is enabled by `.actrc` under `build/cache/act-artifacts/`.
Select a Docker runner image suitable for your host architecture in GitHub
Local Actions. CLI users may pass `-P ubuntu-latest=<runner-image>` to `act`.
Filter a Linux target while testing locally, for example
`act workflow_dispatch --matrix name:alpine-gcc-arm64`, and map its runner label
(`ubuntu-24.04-arm` here) to your local runner image. Include a mapping for
`ubuntu-latest`, which runs validation and generation. The selected target's image
is built by the same workflow. Native Windows/macOS jobs require their native
hosted runners; Linux Docker execution through `act` cannot reproduce them.
No repository access token is required for local validation and generation.
