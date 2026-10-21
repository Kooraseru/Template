# Traits as contracts, not inheritance

Define a trait when callers need to rely on a **behavioral contract** implemented by more than one meaningful type, or when generic bounds are central to the API.

```rust
trait Clock {
    fn now(&self) -> Timestamp;
}

fn create_receipt<C: Clock>(clock: &C) -> Receipt {
    Receipt {
        created_at: clock.now(),
    }
}
```

- Prefer an inherent method for behavior belonging to one type.
- Use generic traits when static dispatch is appropriate; use `dyn Trait` when runtime heterogeneity is a real requirement.
- Avoid empty marker traits or one-method interfaces invented solely for test mocks.
- Keep trait names rooted in capability (`Clock`, `Encode`, `Repository`), not type hierarchies.
- Make object safety, associated types, and lifetime assumptions clear at exported trait boundaries.

Traits are also useful outside OOP: iterators, serialization, arithmetic, and async abstractions use contracts without classical subclassing.
