# LuaCATS annotation shape

Use triple-dash comments for LuaCATS annotations. This check reports a recognized tag written with two dashes, an empty supported tag, or an incomplete @param without a name and type. It reads actual Luau comment tokens.

Moonwave blocks and native Luau types keep their existing roles. Whether documentation is useful, whether tags match the declaration, and whether runtime-specific tags apply require separate review.

See [function documentation](../function-documentation.md), [LuaCATS syntax](https://luals.github.io/wiki/annotations/), and the [fixture matrix](tests/TEST_MATRIX.md).
