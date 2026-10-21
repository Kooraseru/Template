# Repository template contributor source

The `source` branch is authored; `main` is generated publication output. This repository template is application-language agnostic. Optional toolchains and application dependencies belong to each consuming project.

## Entry points

The repository has one public CI command interface:

```bash
bash ci/run.sh validate
bash ci/run.sh rules sync
bash ci/run.sh rules check
bash ci/run.sh configure-editor
bash ci/run.sh local-actions status
bash ci/run.sh native-compat
```

`ci/run.sh` launches `ci/main.luau`, which explicitly dispatches supported operations to domain modules. These do not grant publication authority. GitHub Actions invokes the same interface from jobs with separate permission and evidence boundaries. A local `validate` verifies repository contracts; a hosted run provides platform and publication-specific evidence. No PowerShell wrappers or mandatory application compiler are needed for ordinary validation.

The command-line GitHub Local Actions editor bridge and its requirements are described in [local testing](rules/contracts/repository/local-testing.md). Use its VS Code integration to get extension-owned local workflow History; ordinary Bash validation does not create that History.

## Repository ownership

| Location | Responsibility |
| --- | --- |
| `.github/workflows/ci.yml` | Job orchestration, privileges, evidence transfers, and publication gates |
| `.github/actions/` | Reusable environment setup, not competing CI entry points |
| `ci/integration/` | Hosted GitHub controls and optional editor bridge |
| `ci/fabricator/` | Opt-in compilation targets, distribution packaging, and container images |
| `ci/libraries/` | Shared Luau utilities, data contracts, and test framework |
| `ci/validation/` | Template and repository conformance, policy, and tests |
| `ci/security/` | Publication authorization and signed build receipts |
| `ci/publication/` | Generated repository, documentation, and release publication |
| `config/` | Project publication and explicitly located developer-tool settings |
| `src/` | Optional application code and `build.toml` |
| `rules/` | Tracked Markdown instructions, language guidance, and repository contracts |
| `build/` | Generated outputs and runtime state, Git-ignored |

`AGENTS.md` is generated locally from the tracked rules by `bash ci/run.sh rules sync`; it is **not committed**. No KERO runtime is required.

## Application builds

`config/project.toml` owns repository, Pages, and release publication toggles. `src/build.toml` owns application targets and compiler requirements. It may contain zero targets.

For an optional Rust application, keep all Cargo metadata under `src/cargo/`:

```text
src/
├── build.toml
├── cargo/
│   ├── Cargo.toml
│   ├── Cargo.lock
│   └── config.toml
└── app/
    └── main.rs
```

The fabricator passes the explicit manifest path and optional Cargo `--config` path. No root manifest, mandatory Rust toolchain, or language smoke project exists. Toolchain version and container probes apply only to explicitly selected build environments.

## Security and publication

`source` is the pull request and development branch. `main` is generated only from authorized, validated artifacts. PR or local runs cannot publish; an administrative workflow selection cannot override GitHub permissions. The native primitive compatibility layer uses Node's built-in crypto and ECMAScript number formatting, without Cargo or npm dependencies.

For exact boundaries, read [template architecture](rules/contracts/repository/template-architecture.md), [source updates](rules/contracts/repository/source-updates.md), [build receipts](rules/contracts/repository/build-receipts.md), and [release publication](rules/contracts/repository/releases.md). The [CI architecture](ci/integration/architecture.md) describes job ownership and migration decisions.
