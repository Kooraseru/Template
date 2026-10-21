# Rust executable and library entry points

Executable startup wires dependencies, parses arguments, establishes runtime state, and delegates to application behavior. It must not become an all-purpose implementation file.

- `main` owns startup and top-level exit behavior.
- `lib.rs` exposes a reusable crate surface when the app actually needs one.
- Additional `[[bin]]` targets need explicit ownership, not duplicated startup logic.
- Keep environment validation near entry points, where external values become trusted input.
- Guard against invalid startup states early; return `Result` or a meaningful exit code.
- Keep security or publication permissions separate from optional application code.

A small entry point is intentional:

```rust
fn main() -> Result<(), Error> {
    let config = Config::from_environment()?;
    if !config.enabled() {
        return Ok(());
    }

    app::run(config)
}
```

For this repository's nonstandard Cargo layout, `src/cargo/Cargo.toml` explicitly declares paths to code under `src/app/` (see [manifests](manifests.md)). Rust applications are optional and cannot become prerequisites for Luau CI.
