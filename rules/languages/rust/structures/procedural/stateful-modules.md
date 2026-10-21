# Stateful modules and context passing

Shared mutable state needs a clear owner even when the file's main shape is procedural. Prefer passing a context to operations instead of hiding mutable state in process globals.

```rust
struct ImportContext {
    attempted: usize,
    completed: usize,
}

fn record_success(context: &mut ImportContext) {
    context.attempted += 1;
    context.completed += 1;
}
```

This is still a simple procedural context. It does not require inheritance, interfaces, or a special framework.

Use a state-owning object when instances need independent lifetimes, private invariants, or resource teardown. Use a shared `Arc` only if more than one owner must retain the resource; use `Mutex` only when synchronization is actually needed.

State changes should be observable and testable. Avoid a global `static mut` or magical registry to avoid passing one argument.
