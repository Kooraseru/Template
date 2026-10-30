# Package records

`packages.toml` owns shared GitHub Packages publication policy. Each direct folder
under `records/` is discovered as a separate package; its folder name is its
identity. No central package list is maintained.

Each folder requires:

- `package.toml`: existing build/package files and optional registry metadata.
- `README.md`: the package's own Markdown description, copied into staged output.

For example, copy this shape and fill it with a library you actually build:

```text
records/my-library/
  package.toml
  README.md
```

```toml
# records/my-library/package.toml
files = ["build/MyLibrary.1.0.0.nupkg"]
format = "nuget"
version = "1.0.0"
repository = "your-account/your-repository"
# repository may instead name an explicit alias in repo/config/github.toml.
```

The files must already exist; staging never transforms a binary into a registry
package. Different folders can describe different formats and repositories.
Missing format/version/repository skips registry publication. A configured format
requires a validated registry adapter; none is installed yet. There are no fake
npm, NuGet, Maven, RubyGems, or OCI implementations.

The existing Windows folders are compilation/staging fixtures, with publication
metadata deliberately omitted. They do not define the template's package formats.

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
`../releases/releases.toml` and have their own top-level `release.on_existing`.
Descriptions are staged for a registry adapter to consume; this template does not
claim to update a remote package description without an installed adapter.

Actual credentials belong in GitHub Secrets, never in these files.
