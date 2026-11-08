# Placeholder Luau directory heads

A directory head should own a boundary or coordinate child modules. This validator flags an `init.luau` that returns an empty table, forwards a direct child import, or returns a record made entirely of direct child imports. Local and constant child imports are also covered when the final return forwards every binding. An import absent from the return can have initialization effects and stays for review. The check recognizes quoted child paths beginning with `@self/` or `./`.

A computed path or another resolver convention needs review. A directory head that defines a meaningful API or performs boundary work passes this narrow check.

See [directory roots](../module-roots/README.md) and the [fixture matrix](tests/TEST_MATRIX.md).

## When to use a directory head

`init.luau` is a folder head, not a decoration.

Use it when the folder owns one of these:

- a public contract for a runtime, tool, app, or subsystem
- validation or normalization at the boundary
- lifecycle and setup/teardown
- coordination between private child modules
- a stable facade used by callers

Avoid placeholder folder heads that only mirror child modules.

```text
Render/
  init.luau
  Text.luau
  Layout.luau
```

