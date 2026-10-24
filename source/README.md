# Project source

Create only the source directories your application uses. Language/toolchain
implementation may live under `cargo/`, `cpp/`, or `luau/`. Application-defined
Plugin and Workshop interfaces belong under `api/plugin/` and `api/workshop/`.
Built-in and independently installed plugin implementations belong under
`plugins/builtin/` and `plugins/user/`; authored data-only packages belong under
`workshop/`. Non-installable resources belong under `assets/`.

Declare explicit source target paths and native build systems in
`source/build.toml`. Dependencies and lockfiles belong beside their native manifests,
not in repository tooling. Build commands, compiler requirements, environment
selections, and package paths are source-owned. Paths remain repository-relative.
Repository publication, signing, and release authority remain outside `source/`. No application, provider implementation, runtime sandbox,
or language directory is required by this template. Preflight inspects saved source without executing it. Implementation-specific runtime
checks belong to their owning build/publish stages.

Run the actual CI workflow through
[GitHub Local Actions for VS Code](https://marketplace.visualstudio.com/items?itemName=SanjulaGanepola.github-local-actions).
See the root contributor README for runner mappings and target selection.
