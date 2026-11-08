# Explicit Luau types

The validator reports unqualified `any` type references. Use `unknown` at an unvalidated boundary or describe the value with a structural type. Comments, strings, runtime identifiers, and qualified references are outside this check.

Repeated assertions to the same non-generic type name, including the same module qualifier when present, are flagged on the outer assertion. Identical written structural and generic annotations are also flagged. Different type text is left for review, even when the types might be equivalent. Do not use or export unqualified any. Use a validated boundary or sharpen the type contract instead.

See [Luau type guidance](../../../../rules-old/languages/luau/language/types.md) and the [fixture matrix](tests/TEST_MATRIX.md).
