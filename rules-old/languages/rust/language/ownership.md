# Ownership and borrowing

Express who owns a value and how long access to it is valid. A design with clear ownership usually needs fewer workarounds than one built around unnecessary clones or shared mutable state.

- Borrow with `&T` when reading an existing value.
- Borrow with `&mut T` for exclusive mutation.
- Move a value when ownership genuinely transfers.
- Clone when an independent copy is part of the contract, not merely to appease the compiler.
- Use `Rc`/`Arc` only where shared ownership is real; add `RefCell`/`Mutex` only when mutability and synchronization demand it.
- Do not hide an ownership problem behind broad `Arc<Mutex<_>>` infrastructure before defining resource boundaries.

```rust
fn label<'a>(request: &'a Request) -> Option<&'a str> {
    request.label.as_deref()
}
```

Here the label is borrowed from the request. The explicit lifetime is illustrative; for this single-reference method, Rust often infers it.

**Guard-first borrowing:** use `.as_ref()` or `.as_deref()` when the caller still needs the owner after checking an optional field. A `let Some(value) = request.value else` can partially move an owned field and make later access invalid.

Annotate non-obvious ownership transfers and resource teardown requirements; see [comments](comments.md) and [lifetimes](lifetimes.md).
