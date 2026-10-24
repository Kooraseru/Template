# Repository architecture

- `rules/`: tracked Markdown conventions, contracts, and workflows.
- `config/`: repository and development tooling configuration.
- `source/`: optional application implementation, with source-owned `build.toml`.
- `ci/`: Luau-owned repository orchestration, validation, security, and publication.
- `build/`: disposable generated output, not committed.
- `.github/workflows/ci.yml`: GitHub CI orchestration and separate permission boundaries.

The target command interface is `ci/run.sh` calling `ci/main.luau`. Each domain owns its implementation; domain modules must not become alternative public CI entry points. Internal shell helpers are allowed only when they perform real environment integration.

`source` is authored. `main` is generated publication. Keep publication authority outside `source/`; untrusted application code must not gain access to publishing credentials.

Changes to the current structure are staged. Until cutover, existing implementations and paths must continue to pass current checks.
