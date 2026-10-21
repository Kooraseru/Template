# Functional Rust

Use a functional shape when a function transforms borrowed or owned inputs into an output **without retaining service state or owning a lifecycle**.

Free functions, iterator adaptors, and small closures are normal Rust. They do not need an object with a static method.

```rust
fn clamp_opacity(value: f32) -> f32 {
    value.clamp(0.0, 1.0)
}
```

- Make input and output relationships clear.
- Avoid hidden I/O or mutation of unrelated state.
- Borrow inputs when copying is unnecessary; return owned results when their lifetime must be independent.
- Use explicit `Result` for transformations that can fail.
- Use iterator chains for straightforward mapping/filtering; prefer a loop when validation, mutation, or branching makes a chain hard to read.
- Avoid creating generic combinators before two real callers require the abstraction.

If the operation owns a database connection, manages retries, or coordinates multiple effects, use a procedural service instead. If it owns independently constructed state, consider OOP-like objects.
