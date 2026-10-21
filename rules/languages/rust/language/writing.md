# Writing Rust people can maintain

Good Rust is not the shortest Rust. Favor code whose owner, input contract, failure paths, and mutations can be understood without decoding a sequence of tricks. Optimize a demonstrated bottleneck, not the source's line count.

## Reading order

- Expose **guards first** and keep the normal path below them.
- Give each intermediate result a name if it carries a policy, validation step, or unit conversion.
- Use `match` when branches correspond to meaningful variants; do not hide multi-branch policies in boolean chains.
- Use combinators (`map`, `filter`, `and_then`) for clear transformations; switch to a loop or `match` when control flow, ownership, or side effects matter.
- Prefer a small private helper over duplicated decisions; avoid helpers that only rename one obvious call.
- Keep variable scopes short, mutation local, and return values explicit where that aids comprehension.

```rust
fn selected_ids(items: &[Item]) -> Vec<Id> {
    items
        .iter()
        .filter(|item| item.enabled)
        .map(|item| item.id)
        .collect()
}
```

This pipeline is fine: it is one uncomplicated transformation. For a pipeline requiring validation, logging, and conditional failures, write a readable loop instead.

```rust
fn collect_enabled(items: &[Item]) -> Result<Vec<Id>, Error> {
    let mut selected = Vec::new();

    for item in items {
        if !item.enabled {
            continue;
        }
        validate(item)?;
        selected.push(item.id);
    }

    Ok(selected)
}
```

## API and comments

- Public contracts explain surprising guarantees, effects, panics, errors, and safety obligations using `///`.
- Private comments explain **why** an invariant or ordering exists. Skip headers that merely say “Public Methods,” “Helpers,” or “Fields.”
- Don't create `State` or `Manager` abstractions when a more precise domain name exists.
- Don't hide control flow in macros, `unwrap`, `expect`, clever `Deref` implementations, or operator overloads without a compelling domain reason.
- Format with `rustfmt` for active Rust projects; keep code and comments accurate together.

## Personal conventions translated carefully

The Luau habit “if not, not if” carries over as **guard-first design**, not Luau spelling. Rust's `snake_case`, `PascalCase` types, `Option`/`Result`, `match`, and borrowing rules remain idiomatic. Do not use underscore-prefixed names merely to disguise unused data or private fields; an isolated `_` wildcard is fine. Avoid forcing OOP, ECS, or functional patterns on code that doesn't need them.

The structure documents describe which whole-file ingredients make sense for each responsibility. See [structure selection](../structures/structure-system.md).
