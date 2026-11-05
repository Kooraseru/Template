# Composition and iterator readability

Compose operations when each step has one understandable meaning. Keep validation and side-effect order explicit.

```rust
fn active_ids(items: &[Item]) -> Vec<Id> {
    items
        .iter()
        .filter(|item| item.active)
        .map(|item| item.id)
        .collect()
}
```

This is readable because each step is simple. If errors or resource lifetimes matter, consider explicit iteration:

```rust
fn checked_ids(items: &[Item]) -> Result<Vec<Id>, Error> {
    let mut ids = Vec::new();
    for item in items {
        if !item.active {
            continue;
        }
        validate(item)?;
        ids.push(item.id);
    }
    Ok(ids)
}
```

Avoid nested `map`/`and_then`/`unwrap_or_else` expressions that make the error or happy path difficult to locate. Use `collect::<Result<Vec<_>, _>>()` when a uniformly fallible transformation remains obvious; do not mandate that expression for every pipeline.

If a sequence of steps has policy meaning, give it a named function and test it as a unit.
