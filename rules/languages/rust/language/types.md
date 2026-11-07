# Rust types and invariants

Use the type system to make valid states obvious and invalid combinations harder to construct. Prefer ordinary structs, enums, `Option`, and `Result` to loosely related flags or sentinel values.

```rust
enum Connection {
    Disconnected,
    Connecting,
    Connected { session: SessionId },
}
```

An enum expresses mutually exclusive states better than `connected: bool`, `connecting: bool`, and `session: Option<_>` that can contradict each other.

- Use `struct` for a coherent record, and an `enum` for alternatives.
- Use `Option<T>` for true absence; use `Result<T, E>` for fallibility that callers must handle.
- Introduce newtypes when a domain distinction prevents mistakes, not as an automatic wrapper for every field.
- Keep fields private when the type must preserve invariants; provide narrow constructors and methods.
- Prefer generics for concrete static behavior, trait objects for intentional runtime heterogeneity.
- Avoid `dyn Any`, `Box<dyn Error>`, and unchecked downcasts across domain boundaries where typed contracts are practical.
- Prefer deriving `Debug`, `Clone`, `PartialEq`, etc. only when the semantics of the type justify them.

Document units, lifetime guarantees, and ownership requirements at public boundaries. Let a validated internal type carry trust so every consumer need not repeat the same checks.
