# Project source

Create only the source directories your application uses. Language/toolchain
implementation may live under `cargo/`, `cpp/`, or `luau/`. Application-defined
Plugin and Workshop interfaces belong under `api/plugin/` and `api/workshop/`.
Built-in and independently installed plugin implementations belong under
`plugins/builtin/` and `plugins/user/`; authored data-only packages belong under
`workshop/`. Non-installable resources belong under `assets/`.

Declare explicit source target paths and native build systems in
`config/project.toml`. No application, provider implementation, runtime sandbox,
or language directory is required by this template. Keep tests with their owner;
use the shared testing library for template validation.

Run the actual CI workflow through
[GitHub Local Actions for VS Code](https://marketplace.visualstudio.com/items?itemName=SanjulaGanepola.github-local-actions).
See the root contributor README for runner mappings and target selection.
