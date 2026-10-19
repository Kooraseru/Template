# Project configuration

`project.toml` selects outputs, compiler environments, native tool settings, and
application source targets. The template does not require application source or a
specific language. `source` is authored; `main` is generated after authorization.

## Source targets

```toml
[[targets]]
id = "application"
system = "cargo"
path = "src/cargo"

[[targets]]
id = "native-library"
system = "cmake"
path = "src/cpp/native-library"
```

Target identifiers are unique and safe as output directory names. Paths are
explicit, repository-relative paths; `.` selects the repository root. Cargo
requires a `Cargo.toml`; CMake requires a `CMakeLists.txt`. Unknown systems,
duplicate identifiers, missing manifests, and escaping paths fail validation.
No discovery depends on a conventional language folder existing.

`build.projects` selects source target identifiers. Omit it to build every declared
target; an empty list selects none. `build.targets` and `build.matrix` independently
select compiler environments from `fabricator/targets.json`. An empty environment
selection uses `build.runner`. Source targets are included in artifact fingerprints
and carried with the selected source snapshot, rather than inferred from the
publication controller checkout.

Fabricator invokes the native build tool without an implicit shell. Cargo uses
`build --locked --release`; CMake configures into `build/targets/<id>` and builds
Release. Extra `build.commands` run before source-target compilation. Configure
required tools and `build.package_paths` explicitly. Compilation output belongs
under ignored `build/`; publication consumes completed distributions and evidence.

## Outputs and policy

`repository`, `pages`, `release`, and `images` each have an explicit `enabled` flag.
The first three also have a gated `publish` flag. Local act runs and PRs cannot
publish. Manual controls do not grant authority. Public releases are Release or
Pre-Release SemVer selections in `publication/releases/versions.toml`; replacement
is supported. Internal receipt staging is independent of public releases.

Native setup definitions live under `tools/`. Shared Luau bootstrap utilities and
the locked native canonical-number/Ed25519 helper live under `libraries/bootstrap/`.
That helper is template infrastructure, not a requirement to implement an
application in Rust. Generated binaries stay in `build/native/`.

## Migration status

Directory ownership, shared typed testing, explicit Cargo/CMake source targets,
and generic Plugin/Workshop descriptor checks are implemented. Existing access,
receipts, source protection, and publication gates remain connected to the single
GitHub workflow.

Project-managed Node removal is not complete: receipt collection, release
assembly/publication, remaining JavaScript tests, and PNG rendering still use the
legacy Node setup. Those callers and frozen compatibility cases remain in place
until their Luau/native replacements pass verification. The current tree must not
be advertised as Node-free. Neither worker installation nor runtime sandboxing is
implemented by template validation.
