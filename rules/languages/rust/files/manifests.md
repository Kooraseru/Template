# Rust manifests and configuration

This template intentionally uses `src/cargo/` for application-owned Cargo metadata:

```text
src/
├── build.toml
├── cargo/
│   ├── Cargo.toml
│   ├── Cargo.lock
│   └── config.toml
└── app/
    └── main.rs
```

Use explicit manifest paths: `cargo --manifest-path src/cargo/Cargo.toml build`. Code outside the manifest directory requires explicit `[[bin]]` or `[lib]` paths such as `../app/main.rs`.

`src/cargo/config.toml` is not automatically discovered as Cargo's usual `.cargo/config.toml`; the project fabricator must explicitly supply it with `--config src/cargo/config.toml`.

No root `Cargo.toml`, `src/Cargo.toml`, or hidden `src/.cargo/` is required. The entire `src/cargo/` directory is optional for projects without Rust.
