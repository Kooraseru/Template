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
  content/
    root/                 README, CONTRIBUTING, SECURITY, and other root files
    docs/                 documentation pages
    i18n/                 translations and locale settings
      root/               translations of content/root files
      docs/               translations of documentation pages
    releases/             GitHub Release records and notes
    packages/             GitHub Packages declarations and staging fixtures
  ci/
    entry.luau            executable CI entrypoint
    bootstrap/            component discovery, dependency planning, and scheduling
    components/           discovered build/content-generation components
    dependencies/         CI dependency setup and bootstrap-runtime metadata
    preflight/            plan analysis and diagnostics
      providers/          discovered validators and their own configuration
    github/               optional native Actions job visualization
```

## Where configuration belongs

Keep configuration with the feature that owns it. `repo/config/` holds settings
shared across repository features; it is not a collection of every TOML file.

- `repo/content/i18n/config.toml` defines supported locales and their names.
- `repo/content/releases/releases.toml` defines release records and commit/tag data.
- `repo/content/packages/packages.toml` declares libraries/packages intended for GitHub Packages; fixtures only stage.
- `repo/ci/components/*/component.toml` declares a component's execution contract.
- `repo/ci/preflight/providers/*/config.toml` configures an analyzer beside its code.
- `repo/ci/dependencies/lune/config.toml` pins and verifies the runtime needed to
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
See [CI GitHub integration](ci/github/README.md) for optional job visualization.

`repo/` is editable input. `build/repo/` contains generated repository output.
Edit a root-document template in `repo/content/root/`, not its generated copy.

Credential mappings contain **GitHub secret/variable names only**. Real tokens,
passwords, and private keys stay in GitHub Secrets and must never be committed.
