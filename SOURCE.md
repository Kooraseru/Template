# Source Policy

This document defines what is authoritative, what contributors may edit, and
how generated repository state is produced.

## Sources Of Truth

Canonical source, tests, public documentation, GitHub configuration, and
generation tooling live on `source`. Change behavior by editing its canonical
input, never by patching generated output.

`pre-release` and `release` are automation-owned publication branches. Their
history is disposable. Direct edits and pull requests targeting these branches
are invalid.

## Repository Boundaries

| Surface       | Purpose                                                       | Editable                    |
| ------------- | ------------------------------------------------------------- | --------------------------- |
| `src/`        | Project source when the project defines it                    | Yes                         |
| `tests/`      | Project tests when the project defines them                   | Yes                         |
| `docs/`       | Public rules and project documentation                        | Yes                         |
| `.github/`    | GitHub policy, intake, validation, and publication automation | Yes, with maintainer review |
| `.generated/` | Local build and publication output                            | No                          |
| `pre-release` | Generated preview repository                                  | No                          |
| `release`     | Generated stable repository                                   | No                          |

Personal tooling configuration, private planning, editor state, caches, secrets,
and local build output are not repository source and must not be committed.

## Generated Output

Generators write beneath `.generated/`. MkDocs writes the documentation site to
`.generated/site/`. Publication payloads write beneath
`.generated/repo/<channel>/`.

Generated files must identify or preserve their source provenance. If generated
content is incorrect, fix the canonical source or generator and regenerate it.

Generated publication branches contain `.github/publication.json`, which records
the channel, version, immutable source commit, and generation time.

## Dependencies And Automation

Add a dependency only for an implemented capability with a clear owner. Pin
automation dependencies and third-party GitHub Actions to reviewed immutable
versions. Workflows use least-privilege permissions and must not expose secrets
to untrusted pull-request code.

Non-trivial workflow logic belongs in scripts that run the same way locally and
in GitHub Actions. Do not create local-only validation paths or placeholder
workflows with no active consumer.

## Validation

Every source change must run the relevant repository validation. Changes to
behavior require corresponding tests. Changes to durable contracts require
corresponding documentation updates. Pull requests report the exact commands
and results used for validation.

## Modification Constraints

* Do not bypass branch, review, signing, or publication checks.
* Do not commit secrets, credentials, private reports, or local configuration.
* Do not hand-edit generated branches or generated regions.
* Do not add registries or manifests unless tooling consumes them.
* Keep public rules self-contained and understandable without external configuration.
