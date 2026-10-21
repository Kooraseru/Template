# Rust file and module roles

A module groups a meaningful public responsibility while hiding implementation details. It is not an excuse for an extra forwarding file.

```text
src/
└── app/
    ├── main.rs
    ├── render.rs
    └── render/
        ├── layout.rs
        └── textures.rs
```

The `render.rs` file declares `mod layout;` and `mod textures;` if it owns those children. Use explicit re-exports only when they improve a stable API.

A directory-root `mod.rs` is also supported. Use it as a module boundary when it owns a genuine public contract; it should not exist solely to mirror a directory tree.

- Keep implementation submodules private by default; choose `pub(crate)` and `pub` deliberately.
- Favor one crate until packages have a real independent build/versioning boundary.
- Use `lib.rs` for reusable crate API and `main.rs` for executable startup when those conventional roles apply; custom paths must be declared in Cargo metadata.
- Do not make every file a `struct` with one static method.
- Don't let a module import its children solely to re-export identical names without an actual API benefit.

Module naming and ownership are distinct from manifests. See [manifests](manifests.md) and [module roots](module-roots.md).
