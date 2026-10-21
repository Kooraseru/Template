# Rust expressions

Keep important policy, validation, ownership, and mutation decisions visible. Use expressions as expressions when that reduces noise without hiding which path executes.

```rust
let label = request.label.as_deref().unwrap_or("Untitled");
```

A simple fallback is clear. When absence is a failure, guard it deliberately:

```rust
let Some(label) = request.label.as_deref() else {
    return Err(Error::MissingLabel);
};
```

Choose an idiom based on the information it communicates:

- `if` as an expression is good for one simple choice.
- `match` is good when distinct enum variants or error cases matter.
- `let ... else` is good for one necessary pattern before main logic.
- `?` is good for propagation of `Option`/`Result` without a special branch.
- `map`/`and_then` are good for local transformations; avoid chained closures hiding effects.
- `matches!` is good for a concise shape check, not as an excuse for a large anonymous predicate.

Avoid dense boolean puzzles and gratuitous double negatives. Guard-first means handling blockers early *where that improves the main path*; positive branches remain useful.
