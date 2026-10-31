# Repository support

This directory owns the repository's configuration, authored content, and CI.
Application source lives in `source/`, built-in plugins live in `plugins/`, and
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
  content/
    root/                 README, CONTRIBUTING, SECURITY, and other root files
    docs/                 authored GitHub Pages content
    ci/                   authored CI summaries and authorization messages
    i18n/                 translations and locale settings
      root/               translations of content/root files
      docs/               translations of documentation pages
    releases/             GitHub Release records and notes
    packages/             GitHub Packages declarations and staging fixtures
  ci/
    entry.luau            executable CI entrypoint
    bootstrap/            component discovery, dependency planning, and scheduling
    components/           discovered build/content-generation components
    dependencies/         CI dependency installation code
    preflight/            plan analysis and diagnostics
      providers/          discovered validator implementations
    github/               optional native Actions job visualization
```

## Where configuration belongs

Editable CI settings belong in `repo/config/ci/`; implementation belongs in
`repo/ci/`. Component manifests and native job adapters describe code structure
and remain with that code. Content records stay with their owning content.

- `repo/content/i18n/config.toml` defines supported locales and their names.
- `repo/content/releases/releases.toml` defines release records and commit/tag data.
- `repo/content/packages/packages.toml` owns shared GitHub Packages policy; `packages/records/*/` owns each package and its Markdown description.
- `repo/ci/components/*/component.toml` declares a component's execution contract.
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
preflight engine and its analyzers live under `repo/ci/preflight/`.

The scheduler discovers component and provider packages from their owning
directories. Adding a conforming package does not require a new central list.

`repo/` is editable input. `build/repo/` contains generated repository output.
Edit a root-document template in `repo/content/root/`, not its generated copy.

Credential mappings contain **GitHub secret/variable names only**. Real tokens,
passwords, and private keys stay in GitHub Secrets and must never be committed.
