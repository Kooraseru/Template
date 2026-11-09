# Function ownership in Luau modules

A module that returns an API should keep private functions local and declare methods on its owned table. The validator identifies a top-level bare function declaration that resolves to a global in a file ending in a value-returning statement. It highlights the global name.

It leaves local forward declarations, table methods, and entry points without a final module return outside this check. Global lifecycle callbacks in those entry points require runtime context.

See [Luau function guidance](guidance.md) and the [fixture matrix](tests/TEST_MATRIX.md).
