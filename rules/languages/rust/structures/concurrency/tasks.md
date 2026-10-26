# Task lifetime, cancellation, and communication

Every spawned task must have a comprehensible **owner**, shutdown behavior, error path, and resource budget.

```rust
fn process_all(items: &[Item]) -> Result<(), Error> {
    for item in items {
        if !item.enabled {
            continue;
        }
        process(item)?;
    }
    Ok(())
}
```

This sequential implementation is preferable when no concurrent work is required. Add tasks only when real independent operations justify them.

- Prefer structured task ownership and await/join completion when possible.
- Make cancellation idempotent and release resources in a known order.
- Avoid holding synchronous locks across `.await` unless the lock model explicitly supports and requires it.
- Use bounded channels/queues when producers could outrun consumers.
- Avoid detached tasks whose failures can never be observed.
- Keep blocking work off an asynchronous executor's critical threads.

If an actor alone owns its state, communicate commands and responses rather than exposing its internals via shared mutable references.
