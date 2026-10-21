# Generated Rust and build output

Generated code, bindings, and build products must have one editable source and a reproducible generating operation.

- Make generated files recognizable and document their origin.
- Do not hand-edit generated files; edit the schema or generator and regenerate.
- Put transient compiler output under ignored `build/`, including an explicit `CARGO_TARGET_DIR`.
- Treat generated FFI bindings as untrusted at runtime; type generation doesn't validate external pointers or lengths.
- Keep `Cargo.lock` under `src/cargo/` for the application when present, not under a new repository-level Cargo scaffold.
- Avoid generated module trees with no useful source/owner relationship.

Build declarations belong to `src/build.toml`. The repository does not need Rust source or a Cargo manifest merely because these rules exist.
