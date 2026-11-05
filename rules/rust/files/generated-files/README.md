# Generated Rust and build output

Generated code, bindings, and build products must have one editable source and a reproducible generating operation.

- Make generated files recognizable and identify their producing tool or source.
- Do not hand-edit generated files; edit the schema or generator and regenerate.
- Keep transient compiler output ignored. Use the project's chosen build directory or an explicit `CARGO_TARGET_DIR` when needed.
- Treat generated FFI bindings as untrusted at runtime; type generation does not validate external pointers or lengths.
- Keep the package lockfile and build definitions with their rightful package or application owner.
- Avoid generated module trees with no useful source/owner relationship.

The location of application source and build declarations is project-specific.
