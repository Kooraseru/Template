# Rust objects and owned lifetimes

An object has an identity and/or invariant that belongs to one constructed value. Constructors establish validity; methods preserve it.

```rust
struct Counter {
    value: u64,
}

impl Counter {
    fn new() -> Self {
        Self { value: 0 }
    }

    fn increment(&mut self) {
        self.value += 1;
    }

    fn value(&self) -> u64 {
        self.value
    }
}
```

- Keep fields private if external mutation could violate the contract.
- Use `&self`, `&mut self`, and `self` according to borrowing/moving semantics.
- Use `try_new` for fallible construction rather than hiding failure in `new`.
- Do not copy the same state into multiple objects; choose its authoritative owner.
- Prefer clear composition of fields over inheritance-like indirection.
- Do not use `Arc<Mutex<...>>` to simulate object references without a real concurrent ownership requirement.

An object is not automatically concurrent, serializable, or an ECS entity.
