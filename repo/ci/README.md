# CI implementation

Consumers edit repository settings under `repo/config/`. This directory contains
the scheduler, component implementations, and GitHub adapters.

`components/` supports ordinary grouping folders. Each component owns
`component.toml`, `init.luau`, private implementation modules, and an optional
`github.toml` native adapter. Its identity is its relative directory path.
Capabilities in the manifest define dependencies; grouping does not impose
execution phases or ordering.

The standalone Preflight VS Code extension is recommended in
`.vscode/extensions.json`. It reads `repo/config/ci/preflight.json` and publishes diagnostics
from all active VS Code language providers. CI component discovery and dependency
planning remain owned by `bootstrap/` and `components/`.
