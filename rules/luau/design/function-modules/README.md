# Single-operation Luau modules

The check identifies a standalone module that only wraps one function named exactly like the file. It covers an inline returned table or an empty local table with one dot-style function and an immediate return of that table. A function that uses the module table internally requires review. An existing table API can be part of a caller contract, so this warning offers no automatic edit.

Directory heads, additional exports, and different export names require review. See [function module guidance](../../../../rules-old/languages/luau/structures/functional/function-modules.md) and the [fixture matrix](tests/TEST_MATRIX.md).
