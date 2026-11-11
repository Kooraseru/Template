# Package records

`.github/config/publishing/packages/settings.toml` owns shared GitHub Packages publication policy. Each direct folder
under `.github/config/publishing/packages/` is discovered as a separate package; its folder name is its
identity. No central package list is maintained.

Each folder requires:

- `package.toml`: existing build/package files and optional registry metadata.
- `description.md`: the package's own description, copied into staged output as
  `README.md` so GitHub's package views can render it.

Use `README.md` at a directory level to explain that directory's contents and
conventions. A package record's description belongs in `description.md`.

For example, copy this shape and fill it with a library you actually build:

```text
my-library/
  package.toml
  description.md
```

```toml
# my-library/package.toml
files = ["build/artifacts/MyLibrary.1.0.0.nupkg"]
format = "nuget"
version = "1.0.0"
repository = "your-account/your-repository"
# repository may instead name an explicit alias in .github/config/targets.toml.
```

The files must already exist; staging never transforms a binary into a registry
package. Different folders can describe different formats and repositories.
Missing format/version/repository skips registry publication. A configured format
requires a validated registry adapter; none is installed yet. There are no fake
npm, NuGet, Maven, RubyGems, or OCI implementations.

The existing Windows folders are compilation/staging fixtures, with publication
metadata deliberately omitted. They do not define the template's package formats.
CI accepts the registry publication skip for these fixtures. To publish a package,
add a registry adapter and configure the package metadata.

Shared policy:

```toml
[packages]
on_existing = "replace"
```

- `skip`: preserve an existing remote package version.
- `fail`: stop when that version already exists.
- `replace` (default): replace where the registry and its permissions allow it;
  otherwise fail explicitly. It does not authorize automatic delete/recreate.

GitHub Packages and GitHub Releases are separate. Releases use
`../releases/settings.json` and have their own top-level `release.on_existing`.
Descriptions are staged for a registry adapter to consume; this template does not
claim to update a remote package description without an installed adapter.

Actual credentials belong in GitHub Secrets, never in these files.
