# Enums and explicit state alternatives

Use enums when the valid states are different **shapes**, not just different labels.

```rust
enum Download {
    Pending,
    Active { received: u64, total: Option<u64> },
    Complete { path: std::path::PathBuf },
    Failed { reason: DownloadError },
}
```

A single enum prevents combinations such as `complete = true` while `error` and `active` are also set. Each `match` arm can bind exactly the fields that exist.

- Make variant names describe the state or outcome.
- Avoid wildcard matches for a public enum when new variants should force deliberate review.
- Distinguish absence (`Option`) from domain errors (`Result` or an error enum).
- Use guard-first early return for one rejected variant; use `match` for multiple meaningful alternatives.
- Don't build a custom discriminated union from a tag integer and nullable fields.

Keep enum invariants close to their constructors and transitions; runtime lifecycle rules may belong to a service or object owner.
