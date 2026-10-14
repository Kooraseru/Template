# Repository template — contributor source

This is the development tree for a reusable repository template. Development and
pull requests belong on `source`; `main` contains generated publication output.
The template does not assume a particular application, organization, or language.

For the agreed boundaries and publication rules, read
[the template architecture](.kero/data/contracts/repository/template-architecture.md).

## Running CI locally

Use [GitHub Local Actions for VS Code](https://marketplace.visualstudio.com/items?itemName=SanjulaGanepola.github-local-actions)
to run `.github/workflows/ci.yml` locally through `act`. Install `act` and Docker
for container jobs, open this repository in VS Code, and select **CI** in the
extension's Workflows view. Configure event payloads, runners, inputs, and artifact
options through the extension as needed.

The same workflow defines local and hosted CI. Scripts under `ci/` perform
individual operations; there is no separate local pipeline orchestrator.
Local runs are artifact-only by default. They must not publish remotely.
Native platform jobs still require verification on their appropriate GitHub
runners; sharing a workflow does not guarantee identical host environments.

## Repository responsibilities

- `.github/workflows/ci.yml`: triggers, jobs, dependencies, permissions, and publication gates.
- `.github/actions/`: reusable operation steps.
- `ci/`: validation, building, generation, packaging, and publication implementations.
- `ci/images/`: custom CI Dockerfiles and image definitions.
- `src/`: application source, organized by subsystem.
- `tests/`: tests spanning subsystems.
- `.kero/`: development-tool configuration and state.
- `.kero/data/`: repository contracts, knowledge, and decisions.
- `build/`: disposable generated output, ignored by Git.

Toolchains are optional capabilities. A consumer enables the toolchains and
outputs its project actually uses. Pull requests generate inspectable outputs
without publication privileges. Authorized pushes to `source` may publish those
validated artifacts after all required checks pass.

## Verification

The default artifact-only workflow has passed locally through `act`.
Rust and CMake compilation, image generation, Pages, and release generation
have also passed through the same workflow using test configuration.
Named matrix entries and combined release assembly have passed locally.
Validation rules, policies, test cases, and fixtures are defined in JSON;
Luau executes them. See [declarative checks](ci/validation/README.md).
The final review included Luau analysis, actionlint, shell syntax, configuration
parsing, publication-denial cases, and enabled-output workflow execution.
Repository publication uses GitHub's automatic token. Check the consuming
repository's Actions runs for its hosted publication results.
Native Windows and macOS execution still requires their appropriate hosted runners.

## Configuring a consuming repository

Set its default branch to `source` and target pull requests there.
Edit `ci/config.toml` to select optional outputs, toolchains, and build/test
commands. Commands are argument arrays; use an explicit shell invocation when
a command needs shell syntax. Place all build output under `build/`.
Rust and CMake require explicit versions when enabled.

Set `build.matrix` to named runner entries for multiple build configurations.
Each entry runs the configured commands and receives `CI_BUILD_TARGET` containing
its name. Distribution artifacts and logs are separated by that name; release
assembly verifies and collects every configured distribution. An empty matrix
uses `build.runner` as a single entry named `default`.

Edit publication templates under `ci/repo/templates/`; author release notes
under `ci/releases/records/<version>.md` before selecting that version.
Place custom image Dockerfiles and their build contexts under `ci/images/<name>/`.
Pages uses Markdown templates under `ci/pages/templates/`.

Publication uses the current repository's automatically supplied `GITHUB_TOKEN`;
no PAT, signing key, organization app, or stored secret is required.
For Pages, enable GitHub Actions as the Pages source. Its `github-pages`
deployment environment is created in the consuming repository when used.
Repository branch rules and token permissions
remain authoritative: publication will fail rather than bypass protection.
Allow the workflow's token to update `main` if generated-branch publication
is desired. Signing and external destinations require consumer-specific trusted
jobs; this template supplies no signing credentials.

Approval requirements are optional repository settings. Maintainers may add an
environment with required reviewers to a publication job to pause it for approval
in GitHub. Templates do not transfer those reviewer settings. Approval permits a
job to start; it cannot increase token scopes or override branch protections.
If branch rules require a reviewed change to `main`, use a publication pull
request and merge it through GitHub rather than providing broader credentials.

Local artifact storage is enabled by `.actrc` under `build/act-artifacts/`.
Select a Docker runner image suitable for your host architecture in GitHub
Local Actions. CLI users may pass `-P ubuntu-latest=<runner-image>` to `act`.
No repository access token is required for the default local validation run.
