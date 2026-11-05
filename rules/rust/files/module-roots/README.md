# Rust module roots: `mod.rs` and `name.rs`

Rust has two common ways to represent a module with child modules:

```text
# Directory-root style
render/
  mod.rs
  layout.rs

# File-root style
render.rs
render/
  layout.rs
```

Both can represent the same module. The parent declares `mod render;` once. Do not create both `render.rs` and `render/mod.rs` for the same module: this is ambiguous and duplicates responsibility.

Use `mod.rs` when the directory itself is the coherent module root and a directory facade aids navigation; use `render.rs` when a single file remains a natural owner with child modules. Whichever form is chosen, that root owns public exports and private child declarations.

Rust module resolution is explicit and compile-time: a parent declares `mod render;` and the compiler loads the corresponding module file.

Do not add a module root merely to satisfy symmetry; a lone module can stay a lone file.
