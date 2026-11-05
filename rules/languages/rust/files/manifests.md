# Rust manifests and configuration

Cargo metadata belongs to the package or workspace that owns it. There is no universal repository path for a `Cargo.toml`, `Cargo.lock`, or Cargo configuration.

- Use Cargo's normal conventions when the manifest is at the crate or workspace root.
- If a repository deliberately stores the manifest elsewhere, invoke Cargo with an explicit `--manifest-path`.
- When source files live outside the manifest's directory, use appropriate `[lib]` or `[[bin]]` paths.
- `.cargo/config.toml` follows Cargo's directory lookup conventions. A custom file at another path is **not** automatically discovered; explicitly pass `--config` when needed.
- Track a lockfile according to the consuming project's application/library policy, rather than inventing a second copy.
- Projects without Rust do not need Cargo scaffolding or synthetic compiler examples.
