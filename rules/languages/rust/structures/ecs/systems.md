# ECS systems

Systems process a query result or a clearly scoped group of components. Keep the behavior visible and avoid per-entity branching puzzles.

```rust
fn advance(position: &mut Position, velocity: &Velocity, delta: f32) {
    if delta <= 0.0 {
        return;
    }

    position.x += velocity.dx * delta;
    position.y += velocity.dy * delta;
}
```

A framework-specific system may receive a query rather than two component references; this function illustrates the **responsibility**, not a required ECS framework signature.

- Express read/write access clearly so the scheduler can reason about conflicts.
- Use `continue` for disabled/invalid entities in a loop when skipping is ordinary.
- Report actual failures rather than silently skipping corrupted state.
- Make command-buffer/deferred mutations explicit when immediate entity changes are forbidden.
- Define ordering between systems only where the outcome depends on it.

Prefer systems that describe one operation over large update methods that scan every component of every entity.
