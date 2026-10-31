# CI implementation

Consumers edit repository settings under `repo/config/`. This directory contains
the scheduler, component implementations, GitHub adapters, and preflight engine.

`components/` supports ordinary grouping folders. Each component owns
`component.toml`, `init.luau`, private implementation modules, and an optional
`github.toml` native adapter. Its identity is its relative directory path.
Capabilities in the manifest define dependencies; grouping does not impose
execution phases or ordering.

Preflight implementations live in the repository-root `providers/` directory;
CI tool installation implementations live in the repository-root `dependencies/`.
Their settings remain under `repo/config/ci/`.
