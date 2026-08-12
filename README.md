# Template Source

This is the canonical `source` branch for the reusable repository template.
Contributors change source, documentation, localization, automation, and
publication tooling here. Automation generates `canary`, `beta`, and `stable`
channel branches from an exact source commit or local snapshot.

## Start Here

- [Repository architecture](docs/architecture/repository.md) defines source,
  generated output, content ownership, and branch roles.
- [Contribution guidelines](.github/CONTRIBUTING.md) define the contributor
  workflow and validation expectations.
- [Development and validation](docs/development/validation.md) lists local and
  GitHub Actions entry points.
- [Translation guide](TRANSLATORS.md) explains keyed templates, adjacent
  catalogs, and fallback behavior.
- [Security policy](.github/SECURITY.md) explains private vulnerability reporting.
- [Publication configuration](.github/publication/config.yml) defines the public
  generated-repository whitelist.

## Repository Locations

<table>
  <tr>
    <td><code>.github/</code></td>
    <td>GitHub policy, automation, and publication tooling</td>
  </tr>
  <tr>
    <td><code>.vscode/</code></td>
    <td>shared editor and local task entry points</td>
  </tr>
  <tr>
    <td><code>content/</code></td>
    <td>localized Pages and repository inputs plus public assets</td>
  </tr>
  <tr>
    <td><code>docs/</code></td>
    <td>English source architecture and project contracts</td>
  </tr>
  <tr>
    <td><code>.generated/</code></td>
    <td>ignored MkDocs and repository outputs</td>
  </tr>
</table>

The root source `README.md`, `.github/CONTRIBUTING.md`, `.github/LICENSE`, and
other canonical control files are maintained in English. Localized repository
and Pages content is generated from adjacent templates and TOML catalogs under
`content/`.

Do not edit `canary`, `beta`, `stable`, or files beneath `.generated/` as source.
