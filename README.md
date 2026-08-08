# Repository Template

This repository is a reusable source, documentation, GitHub automation, and
publication shell. Projects adopt the boundaries here, then add only the source
domains, tests, dependencies, and public content they actually use.

## Start Here

- [`SOURCE.md`](SOURCE.md) defines authored and generated source boundaries.
- [`.github/CONTRIBUTING.md`](.github/CONTRIBUTING.md) defines the contributor
  workflow.
- [`docs/`](docs/) contains human-readable architecture, development, and
  standards documentation.
- [`.github/SECURITY.md`](.github/SECURITY.md) defines private vulnerability
  reporting.

## Branches And Publication

Humans author on `source`. Automation builds the disposable `pre-release` and
`release` branches from an immutable source commit. Publication is disabled by
default until a project declares an explicit public-file whitelist in
`.github/publication/config.yml`.

MkDocs builds the public documentation into `.generated/site/`; generated
output is never committed as source.

## Adopting The Template

Before the first release, replace this overview with the project identity,
select and add the intended license, configure publication files, enable the
appropriate CodeQL language, and configure GitHub branch protections,
environments, Pages, Discussions, and private vulnerability reporting.
