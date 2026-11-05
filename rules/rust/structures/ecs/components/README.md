# ECS components

Components are **small, cohesive pieces of data** that systems can query. Their structure reflects the domain rather than an object method table.

```rust
struct Position {
    x: f32,
    y: f32,
}

struct Velocity {
    dx: f32,
    dy: f32,
}
```

- Keep component fields coherent and explicit.
- Prefer typed states to magic numbers or arbitrary strings.
- Do not hide cross-entity effects inside component getters or constructors.
- Let the ECS storage own component lifetime, unless the chosen framework provides a different documented contract.
- Avoid packing unrelated resources into one universal "entity state" component.

Use component marker traits or derive macros only if the actual ECS library requires them. No ECS dependency or generated boilerplate is required for application projects that do not use ECS.
