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

- [Additional metamethod](invalid/inheritance-with-metamethod.luau) reports the inheritance link alongside another metamethod.
- [Computed key](review/computed-inheritance-key.luau) stays for review because the computed key could replace the explicit link.

- [Quoted inline fields](invalid/quoted-inline-fields.luau) reports a populated instance table with a literal bracket key.
- [Computed inline fields](review/computed-inline-fields.luau) keeps a computed key outside the check.
