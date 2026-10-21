# Rust structure and writing system

Rust has no universal file skeleton. First identify *what the code owns*, then pick the appropriate file role and structural family, and only then apply general language conventions.

```text
rust/
├── rust-system.md
├── language/
│   ├── naming.md
│   ├── types.md
│   ├── functions.md
│   ├── expressions.md
│   ├── control-flow.md
│   ├── errors.md
│   ├── ownership.md
│   ├── lifetimes.md
│   └── writing.md
├── files/
│   ├── modules.md
│   ├── module-roots.md
│   ├── manifests.md
│   ├── entry-points.md
│   └── generated-files.md
└── structures/
    ├── structure-system.md
    ├── data/
    ├── functional/
    ├── procedural/
    ├── oop/
    ├── ecs/
    ├── concurrency/
    └── ffi/
```

Choose in this order:

1. **Responsibility:** value transformation, retained state, lifecycle, external I/O, systems processing, or boundary adaptation
2. **File role:** public module root, private child module, executable entry, generated code, or data definition
3. **Structure:** functional, procedural, OOP, ECS, data, concurrency, or FFI
4. **Language conventions:** naming, types, borrowing, errors, guard-first control flow, and source readability
5. **Structure-specific contracts:** what that structure requires, allows, and deliberately omits

The structure is for maintainers, not for persuading the compiler. A `struct` alone does not imply OOP; a `trait` alone does not imply an abstract class; a `mod.rs` alone does not require a façade. Preserve one useful owner for each behavior.

Rust differs from Luau in ownership, borrowing, algebraic data types, and compilation. Translate the *reasoning* of the Luau rules—clear guards, small responsibilities, deliberate composition—not its syntax or camelCase/PascalCase spellings.
