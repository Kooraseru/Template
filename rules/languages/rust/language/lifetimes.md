# Lifetimes

A lifetime describes the validity relationship of borrowed references; it is not a runtime timer, resource scheduler, or ownership substitute.

Prefer an owned result when data must survive after the input is dropped. Prefer a borrowed result when callers only need a view into existing input. Let lifetime elision handle ordinary single-source references.

When multiple inputs can supply a return value, state their shared relationship explicitly:

```rust
fn chosen_label<'a>(primary: &'a str, fallback: &'a str, prefer_primary: bool) -> &'a str {
    if prefer_primary {
        primary
    } else {
        fallback
    }
}
```

An explicit lifetime makes clear that the returned reference cannot outlive the referenced input. Do not add lifetime parameters that convey no meaningful relationship.

Avoid putting borrowed fields into persistent service structs unless the caller can guarantee the owner lives long enough. Prefer owned buffers, IDs, or handles for independently retained state. Document safety invariants wherever `unsafe` manipulates raw pointers or reference lifetimes.

Lifetimes are Rust-specific constraints; preserve Luau's intent to make ownership clear, not its reference semantics.
