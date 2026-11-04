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
    ci/                   editable CI policies and tool pins
      preflight.json      workspace plan consumed by the recommended extension
      execution.toml      default and per-component runtime skip policy
      dependencies/       CI runtime/tool versions and checksums
      authorization/      requested App permissions and classic PAT scopes
      responses/          two root responses, templates, layout, and color mappings
  content/
    files/                README, CONTRIBUTING, SECURITY, and other root files
    docs/                 authored GitHub Pages content
    i18n/                 translations and locale settings
      files/              translations of content/files
      docs/               translations of documentation pages
    releases/             GitHub Release records (JSON) and notes
    packages/             GitHub Packages declarations and staging fixtures
  ci/
    entry.luau            executable CI entrypoint
    bootstrap/            component discovery, dependency planning, and scheduling
    components/           recursively discovered component packages and groupings
      build/              application, package, page, and release preparation
      publish/            publication and provenance components
      repository/         branch generation and GitHub resource synchronization
    github/               optional native Actions job visualization
    rendering/            shared content rendering implementation
```

`dependencies/` is a sibling of `repo/` at the repository root and owns CI tool
installation implementations. Its editable settings live in
`repo/config/ci/dependencies/`.

## Where configuration belongs

Editable CI settings belong in `repo/config/ci/`; implementation belongs in
`repo/ci/`. Component manifests and native job adapters describe code structure
and remain with that code. Content records stay with their owning content.

- `repo/content/i18n/config.toml` defines supported locales and their names.
- `repo/content/releases/releases.json` defines release records and commit/tag data.
- `repo/content/packages/packages.toml` owns shared GitHub Packages policy; each `packages/records/*/` folder owns its `package.toml` and `description.md`.
- `repo/config/ci/components.toml` enables or disables discovered components.
- `repo/ci/components/**/component.toml` declares a component's execution contract.
- `repo/config/ci/dependencies/lune.toml` pins and verifies the runtime needed to
  start Luau. It does not declare application dependencies.

## Entry points and generated output

`.github/`, `.vscode/`, `.codex/`, and `.luaurc` remain at the locations their
platforms expect. They point into this directory rather than duplicating pipeline
definitions. The existing `@ci` import alias resolves to `repo/ci/`.
VS Code recommends the standalone `Kooraseru-Hub/Preflight` extension through
`.vscode/extensions.json`. Its workspace plan is
`repo/config/ci/preflight.json`, selected through the documented VS Code setting.
The extension publishes diagnostics from all active VS Code language providers through its
documented local API; the local Codex hook reads that API before and after edits.

The scheduler discovers component packages from their owning directories.
Adding a conforming component does not require a new central list.
Component groupings are ordinary directories. A component has both
`component.toml` and `init.luau`; its identity is its relative path, such as
`releases/publish`. Component internals are private and are not discovered as
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
```

Package and release staging skips when there are no records. Disabled components
produce no output on a fresh run; Pages output is created by the enabled Pages
builder. Application consumers, manifests, and artifact transfers must use the
same paths. Keep diagnostic captures under the corresponding `run/<workflow>/logs/`
and generated previews under `responses/`, rather than at the build root.
The entire `build/` directory is ignored and can be removed before a fresh build.

Run **CI: Run local workflows** from VS Code tasks, or run
`bash dependencies/local-actions/run.sh`, to execute CI Start and then its
generated CI Execution graph with `act`. Local runs use a private artifact store
and the artifact actions supported by `act`; they skip GitHub publication,
remote Check Runs, signing, and branch cleanup. Logs are saved under
`build/run/local-actions/logs/`. GitHub-hosted workflows retain their configured
publication and reporting behavior.

PRs targeting `source` run a read-only bootstrap and the required `gate` check.
Internal PRs can generate a separate native CI Execution graph using the
configured GitHub App or bootstrap token. Gate depends on bootstrap's completed
execution result; its success does not merely mean the graph was scheduled.
Fork PRs use the read-only local scheduler without credentials. Neither PR mode
selects privileged publication components.

VS Code tasks use `bash` from `PATH`; configure MSYS2 Bash in the editor
environment on Windows.

`github/project-plans/index.json` is a validated snapshot of the blueprints in
`repo/config/projects/`. The read-only `projects/plan` component
checks them on pushes, pull requests, and manual runs. It does not create GitHub
Projects. The privileged `projects/sync` component depends on that validation,
re-reads the source definitions, and reconciles the actual projects on pushes.
Its result is recorded under `github/project-sync/`.

Project blueprints are individual TOML files with fields and multiple views;
see `repo/config/projects/README.md` for supported view properties.
Repository rulesets use the same flat-file convention under
`repo/config/rulesets/`. The read-only `rulesets/plan` validates rulesets on
PRs, and `rulesets/sync` uses separate Administration: write authorization on
source pushes. Neither system creates Project items or issues.

Credential mappings contain **GitHub secret/variable names only**. Real tokens,
passwords, and private keys stay in GitHub Secrets and must never be committed.
