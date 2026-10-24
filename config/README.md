# Project configuration

`project.toml` controls repository, Pages, and release publication.
`source/build.toml` owns application targets, compiler requirements, environment
selections, commands, and package contents. Native dependencies and lockfiles
stay alongside their source manifests. The template does not require application source or a
specific language. `source` is authored; `main` is generated after authorization.

## Source-owned build configuration

The following declarations belong in `source/build.toml`:

```toml
[[targets]]
id = "application"
system = "cargo"
path = "source/cargo"

[[targets]]
id = "native-library"
system = "cmake"
path = "source/cpp/native-library"
```

Target identifiers are unique and safe as output directory names. Paths are
explicit, repository-relative paths; `.` selects the repository root. Cargo
requires a `Cargo.toml`; CMake requires a `CMakeLists.txt`. Unknown systems,
duplicate identifiers, missing manifests, and escaping paths fail validation.
No discovery depends on a conventional language folder existing.

`build.projects` selects source target identifiers. Omit it to build every declared
target; an empty list selects none. `build.targets` and `build.matrix` independently
select compiler environments from `ci/fabricator/targets.json`. An empty environment
selection uses `build.runner`. Source targets are included in artifact fingerprints
and carried with the selected source snapshot, rather than inferred from the
publication controller checkout.

Fabricator invokes the native build tool without an implicit shell. Cargo uses
`build --locked --release --manifest-path <path>/Cargo.toml` and also passes `--config <path>/config.toml` when that optional file exists; CMake configures into `build/targets/<id>` and builds
Release. Extra `build.commands` run before source-target compilation. Configure
required tools and `build.package_paths` explicitly. Compilation output belongs
under ignored `build/`; publication consumes completed distributions and evidence.

## Outputs and policy

Repository-owned `repository`, `pages`, and `release` each have explicit `enabled`
and gated `publish` flags. Source-owned `images` selects optional build environments
and has an `enabled` flag; it cannot grant publication authority. Local act runs and PRs cannot
publish. Manual controls do not grant authority. Public releases are Release or
Pre-Release SemVer selections in `ci/publication/releases/versions.toml`; replacement
is supported. Internal receipt staging is independent of public releases.

Native setup definitions live under `tools/`. Shared Luau bootstrap utilities and
the locked native canonical-number/Ed25519 helper live under `ci/libraries/bootstrap/`.
That helper is template infrastructure, not a requirement to implement an
application in Rust. Generated binaries stay in `build/native/`.

## Migration status

Directory ownership, shared typed testing, explicit Cargo/CMake source targets,
and generic Plugin/Workshop descriptor checks are implemented. Existing access,
receipts, source protection, and publication gates remain connected to the single
GitHub workflow.

Project-managed Node and the JavaScript interoperability layer have been removed.
Receipt collection/authentication/reuse, release planning/assembly/publication, and
their tests call Luau modules directly. Native primitives own Ed25519, exact number
formatting, external key files, UUIDs, and SVG-to-PNG rendering. The licensed graph
font is under `ci/publication/releases/assets/`. The native dependency lockfile and
frozen canonical/signature vectors remain checked in.

Stock GitHub actions may use Node internally; this template installs no Node
runtime or executes project JavaScript in CI. The optional editor-host adapter
uses VS Code's built-in extension API without npm dependencies. Worker installation and runtime
sandboxing remain application responsibilities.
