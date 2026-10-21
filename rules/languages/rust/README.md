# Rust language conventions

Rust is an **optional application language**. This repository's CI remains Luau-owned; Rust rules do not require Cargo, a Rust project, or language smoke tests in the base template.

Read [`rust-system.md`](rust-system.md) to choose a file's responsibility, then the applicable rules:

- [`language/`](language/): naming, good writing, control flow, expressions, functions, types, ownership, lifetimes, and error semantics
- [`files/`](files/): package manifests, module roots, executable boundaries, and generated output
- [`structures/`](structures/): select functional, procedural, object-oriented, data, ECS, concurrency, or FFI shapes **by responsibility** rather than aesthetics

The Luau philosophy **“if not, not if”** is carried across as a *guard-first reasoning principle*: reject an invalid state, then let the valid path remain readable. In Rust, this can mean `if !condition { return ...; }`, `let Some(value) = input else { ... };`, `?`, `continue`, or a focused `match`. It does **not** mean mechanically negating every `if`.

See [Rust control flow](language/control-flow.md) and [good writing](language/writing.md). Follow idiomatic Rust spelling (`snake_case`) rather than copying Luau's exported-method naming conventions.
