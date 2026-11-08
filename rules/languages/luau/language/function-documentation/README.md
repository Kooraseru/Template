# LuaCATS annotation shape

Use triple-dash comments for LuaCATS annotations. This check reports a recognized tag written with two dashes, an empty supported tag, or an incomplete @param without a name and type. It reads actual Luau comment tokens.

A triple-dash documentation block immediately above a named function also warns on a simple `@param` name absent from the declaration. Detached comments, nested parameter fields, and Moonwave blocks require separate review. Native Luau types continue to describe the signature.

Attached function documentation rejects `@readonly`, which describes properties, and `@function` or `@method` tags that redeclare an existing function.

See [function documentation](../function-documentation.md), [LuaCATS syntax](https://luals.github.io/wiki/annotations/), and the [fixture matrix](tests/TEST_MATRIX.md).
