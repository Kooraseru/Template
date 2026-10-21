# Data structures

Data files describe values and their invariants, not runtime coordination. Use structs for grouped fields and enums for mutually exclusive alternatives.

Choose data structures when callers need to **read, construct, serialize, validate, or compare** a value. If the type owns open resources or coordinates a lifecycle, consult [objects](../oop/objects.md) instead.

```rust
#[derive(Debug, Clone, PartialEq, Eq)]
struct BuildTarget {
    name: String,
    platform: Platform,
}

#[derive(Debug, Clone, PartialEq, Eq)]
enum Platform {
    Linux,
    Windows,
    MacOs,
}
```

- Name fields for the domain and keep them coherent.
- Store one authoritative value; derive or compute redundant views.
- Choose variants rather than loosely related booleans.
- Make invalid public combinations impossible or validate at construction.
- Derive traits only when equality, copying, hashing, or logging has meaningful semantics.
- Avoid storing cached runtime handles in otherwise declarative configuration merely for convenience.

Data is not a "dumb" lesser form of OOP; it is often the correct boundary for format, configuration, and state snapshots.

[Example data record](examples/build_target.rs) illustrates the structure without adding a mandatory application or CI smoke test.
