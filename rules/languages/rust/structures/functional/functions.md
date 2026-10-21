# Pure and near-pure functions

Use free functions for cohesive transformations. Prefer inputs over hidden global configuration, even if a function's output is small.

```rust
fn normalized_name(input: &str) -> String {
    input.trim().to_lowercase()
}
```

The output depends on the input. A function that reads a file or changes a global setting may still be a valid **free function**, but it is not pure: make the effect obvious by its name and call boundary.

Guard-first works here too:

```rust
fn first_visible(items: &[Item]) -> Option<&Item> {
    for item in items {
        if !item.visible {
            continue;
        }
        return Some(item);
    }
    None
}
```

Prefer this explicit loop to a complicated closure if visibility requires multiple checks. If the predicate is a simple field read, `items.iter().find(|item| item.visible)` is equally clear. Do not outlaw idiomatic Rust merely to reproduce a Luau loop.
