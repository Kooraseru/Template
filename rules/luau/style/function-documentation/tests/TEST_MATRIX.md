# Function documentation fixture matrix

- [Malformed tags](invalid/malformed-tags.luau) has a two-dash annotation and an empty return tag.
- [Documented function](valid/documented-function.luau) passes.
- [Method parameters](valid/method-parameters.luau) accepts an optional parameter tag and the implicit receiver.
- [Moonwave and string](valid/moonwave-and-string.luau) passes because block comments and strings are outside the rule.
- [Parameter binding](invalid/parameter-binding.luau) reports a tag left behind after a parameter rename.
- [Detached documentation](review/detached-doc.luau) has an ambiguous owner and produces no warning.
- [Function metadata](invalid/function-metadata.luau) reports property metadata and a redundant declaration tag on a named function.
- [Property metadata](valid/property-metadata.luau) accepts a readonly annotation on a binding and lifecycle metadata on a function.
