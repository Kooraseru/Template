# Placeholder Luau directory heads

A directory head should own a boundary or coordinate child modules. This validator flags an `init.luau` that returns an empty table, forwards a direct child import, or returns a record made entirely of direct child imports. Forwarding through one local or constant binding is also covered. The check recognizes quoted child paths beginning with `@self/` or `./`.

A computed path or another resolver convention needs review. A directory head that defines a meaningful API or performs boundary work passes this narrow check.

See [init files](../init-files.md), [directory roots](../module-roots.md), and the [fixture matrix](tests/TEST_MATRIX.md).
