# Function documentation fixture matrix

- [Malformed tags](invalid/malformed-tags.luau) has a two-dash annotation and an empty return tag.
- [Documented function](valid/documented-function.luau) passes.
- [Moonwave and string](valid/moonwave-and-string.luau) passes because block comments and strings are outside the rule.
- [Parameter binding](review/parameter-binding.luau) requires a separate declaration-aware check.
