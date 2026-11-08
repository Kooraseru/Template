# Explicit Luau types

The validator reports unqualified `any` type references. Use `unknown` at an unvalidated boundary or describe the value with a structural type. Comments, strings, runtime identifiers, and qualified references are outside this check.

Repeated assertions to the same non-generic type name, including the same module qualifier when present, are flagged on the outer assertion. A sequence of assertions to different types requires review of the boundary and the validation around it.

See [Luau type guidance](../../../../rules-old/languages/luau/language/types.md) and the [fixture matrix](tests/TEST_MATRIX.md).
