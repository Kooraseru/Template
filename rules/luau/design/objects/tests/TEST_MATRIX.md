# Instance construction fixtures

- [Inline fields](invalid/inline-fields.luau) highlights the populated table.
- [Fields first](valid/fields-first.luau) passes.
- [Dynamic metatable](review/dynamic-metatable.luau) produces no warning. The called expression can implement a non-instance boundary.
- [External metatable](review/external-metatable.luau) produces no warning. A local import does not establish ownership of the metatable.

- [Implicit receiver](invalid/implicit-receiver.luau) reports the qualified method name.
- [Untyped receiver](invalid/untyped-receiver.luau) highlights the untyped explicit `self` parameter.
- [Different receiver name](review/different-receiver-name.luau) produces no finding because dot declarations can also be static functions.
- [Reassigned metatable](review/reassigned-metatable.luau) produces no receiver finding because table ownership may have changed.
- [Explicit receiver](valid/explicit-receiver.luau) passes with dot syntax.
- [External receiver](review/external-receiver.luau) produces no warning because the external API owns the calling convention.

- [Class inheritance](invalid/class-inheritance.luau) highlights the base-class link.
- [Instance index](valid/instance-index.luau) passes because the index resolves to its own class.
- [Lookup metatable](review/lookup-metatable.luau) produces no finding. A lookup default is not enough evidence of class inheritance.
