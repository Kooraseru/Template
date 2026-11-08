# Rust code organization

Choose a structure for what the code **does and owns**, not because a language feature exists. There is no mandatory file skeleton.

```text
rust/
├── rust-system.md
├── language/
│   ├── writing.md
│   ├── comments.md
│   ├── control-flow.md
│   ├── naming.md
│   ├── types.md
│   ├── functions.md
│   ├── expressions.md
│   ├── errors.md
│   ├── ownership.md
│   └── lifetimes.md
├── files/
│   ├── modules.md
│   ├── module-roots.md
│   ├── entry-points.md
│   ├── generated-files.md
│   └── manifests.md
└── structures/
    ├── structure-system.md
    ├── data/
    ├── functional/
    ├── procedural/
    ├── oop/
    ├── ecs/
    ├── concurrency/
    └── ffi/
```

Review a file in this order:

1. **Responsibility:** data representation, pure transformation, coordination, instance lifetime, entity processing, concurrency, or external ABI
2. **Module role:** public root, private child, entry point, or generated boundary
3. **Structure family:** only the one(s) justified by the behavior
4. **Language conventions:** Rust-native naming, ownership, error types, guard clauses, and expression readability
5. **Documentation:** Rustdoc for API contracts; inline comments for phases, invariants, non-obvious decisions, and complicated algorithms

Do not infer OOP from the presence of a `struct`, inheritance from `trait`, or the need for a facade from a directory. A design should minimize competing owners and moving parts.

**Long functions are a warning to inspect, not a license to remove comments.** First identify named phases and annotate their intent. Extract helpers where each phase has a meaningful contract and testable outcome. Avoid fragmenting one readable algorithm into dozens of one-line forwarding functions.

When code validates external data and then traverses it, readers should be able to locate these phases immediately: **input constraints → numeric/structural invariants → traversal rules → construction/commit**. This is a responsibility-based navigation aid, not a required set of decorative section banners. See [comments](language/comments.md).
