# Rust conventions

These rules describe **how to write and organize Rust code**. They are self-contained: no prior knowledge of another language, runtime, or repository automation system is needed.

Start with [the Rust system](rust-system.md). Select a file's responsibility, its module role, and the appropriate structural family. Apply the language rules throughout.

- [Language](language/): [writing](language/writing.md), [comments](language/comments.md), [control flow](language/control-flow.md), [functions](language/functions.md), [expressions](language/expressions.md), naming, types, errors, ownership, and lifetimes
- [Files](files/): modules, module roots, entry points, generated files, and manifests
- [Structures](structures/structure-system.md): data, functional, procedural, owned objects, ECS, concurrency, and FFI

**House style:** make the main path easy to follow. Reject unmet preconditions early where appropriate; use `let ... else`, `?`, `match`, and explicit branches according to their actual semantics. Never manufacture negations or conceal errors to satisfy a slogan.

**Documentation is required at meaningful boundaries.** Public APIs need Rustdoc contracts. Dense validation, traversal, state machines, unsafe/FFI code, numeric constraints, and multi-phase algorithms need nearby explanation of intent and invariants. Comments should make it possible to navigate the code without reverse engineering each expression.

Project-specific build layouts belong to [manifests](files/manifests.md); these writing conventions apply to Rust whether the project uses Cargo or compiles via another supported workflow.
