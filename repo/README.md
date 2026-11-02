# Repository support

This directory owns the repository's configuration, authored content, and CI.
Application source lives in `source/`, built-in plugins live in `plugin/`, and
generated results live in `build/`.

```text
repo/
  config/                 shared repository and tooling settings
    github.toml           repository paths, aliases, credential names, branch policy
    luau/                 shared editor/analyzer/formatter settings
    docker/               local Actions/Docker runner settings
    ci/                   editable CI policies, provider settings, and tool pins
      execution.toml      default and per-component runtime skip policy
      preflight/          settings matched to discovered analyzer identities
      dependencies/       CI runtime/tool versions and checksums
      authorization/      requested App permissions and classic PAT scopes
      responses/          two root responses, templates, layout, and color mappings
  content/
    files/                README, CONTRIBUTING, SECURITY, and other root files
    docs/                 authored GitHub Pages content
    i18n/                 translations and locale settings
      files/              translations of content/files
      docs/               translations of documentation pages
    releases/             GitHub Release records and notes
    packages/             GitHub Packages declarations and staging fixtures
  ci/
    entry.luau            executable CI entrypoint
    bootstrap/            component discovery, dependency planning, and scheduling
    components/           recursively discovered component packages and groupings
      build/              application, package, page, and release preparation
      publish/            publication and provenance components
      repository/         branch generation and GitHub resource synchronization
    preflight/            plan analysis and diagnostics
    github/               optional native Actions job visualization
    rendering/            shared content rendering implementation
```

`providers/` and `dependencies/` are siblings of `repo/` at the repository root.
They own validator and CI tool installation implementations. Their editable
settings live in `repo/config/ci/preflight/` and `repo/config/ci/dependencies/`.

## Where configuration belongs

Editable CI settings belong in `repo/config/ci/`; implementation belongs in
`repo/ci/`. Component manifests and native job adapters describe code structure
and remain with that code. Content records stay with their owning content.

- `repo/content/i18n/config.toml` defines supported locales and their names.
- `repo/content/releases/releases.toml` defines release records and commit/tag data.
- `repo/content/packages/packages.toml` owns shared GitHub Packages policy; each `packages/records/*/` folder owns its `package.toml` and `description.md`.
- `repo/config/ci/components.toml` enables or disables discovered components.
- `repo/ci/components/**/component.toml` declares a component's execution contract.
- `repo/config/ci/preflight/*.toml` configures each discovered analyzer.
- `repo/config/ci/dependencies/lune.toml` pins and verifies the runtime needed to
  start Luau. It does not declare application dependencies.

For example, the i18n validator's configuration enables validation; the content
locale configuration defines the languages being validated. They have different
owners and do not duplicate one another.

## Entry points and generated output

`.github/`, `.vscode/`, `.codex/`, and `.luaurc` remain at the locations their
platforms expect. They point into this directory rather than duplicating pipeline
definitions. The existing `@ci` import alias resolves to `repo/ci/`.
The VS Code Problems-panel integration lives in `.vscode/preflight/`; the
preflight engine lives under `repo/ci/preflight/` and discovers analyzers from
the repository-root `providers/` directory.

The scheduler discovers component and provider packages from their owning
directories. Adding a conforming package does not require a new central list.
Component groupings are ordinary directories. A component has both
`component.toml` and `init.luau`; its identity is its relative path, such as
`publish/releases`. Component internals are private and are not discovered as
additional components. Consumer settings belong in `config/`; runtime code and
component manifests are maintained as implementation.

`repo/` is editable input. `build/github/` contains generated repository output.
Edit a root-document template in `repo/content/files/`, not its generated copy.

Generated output follows this layout (folders appear only when used):

```text
build/
  github/
    branches/<branch>/
    packages/<package>/
    releases/<version>/
    pages/
    project-plans/
    project-sync/
    attestations/
  run/
    ci-execution/
      artifacts/application/   compiled application files
      artifacts/*.tar          component output transfers
      responses/               response fragments and execution.md
      logs/                    component and report logs
    ci-start/                  bootstrap artifacts, responses, and logs
    dependencies/artifacts/    downloaded CI tools
    preflight-extension/artifacts/  local VSIX and installation stamps
```

Package and release staging skips when there are no records. Disabled components
produce no output on a fresh run; Pages output is created by the enabled Pages
builder. Application consumers, manifests, and artifact transfers must use the
same paths. Keep diagnostic captures under the corresponding `run/<workflow>/logs/`
and generated previews under `responses/`, rather than at the build root.
The entire `build/` directory is ignored and can be removed before a fresh build.

Credential mappings contain **GitHub secret/variable names only**. Real tokens,
passwords, and private keys stay in GitHub Secrets and must never be committed.
