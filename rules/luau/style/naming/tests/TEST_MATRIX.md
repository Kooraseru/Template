# Luau type-alias naming fixtures

- [PascalCase](valid/pascal-case.luau) passes, including acronyms, digits, and optional numeric separators.
- [Bad alias names](invalid/bad-alias-names.luau) reports both declaration names.
- [Foreign type name](review/foreign-type-name.luau) produces no warning. Naming a type from another module is that module's responsibility.

- [Bad parameters](invalid/bad-parameters.luau) reports both identifiers.
- [Parameters](valid/parameters.luau) passes with camelCase and an ignored argument.
- [External field](review/external-field.luau) produces no warning. Field naming depends on who owns the record contract.
- [Local helpers](valid/local-helpers.luau) passes with camelCase helpers and a PascalCase member of a returned module table.
- [Bad local helpers](invalid/bad-local-helpers.luau) reports uppercase and underscore-prefixed declarations, including a function expression bound to a constant.
- [Required modules](valid/required-modules.luau) passes for direct PascalCase bindings.
- [Bad required modules](invalid/bad-required-modules.luau) reports lowercase and underscore-separated bindings.
- [Custom loaders](review/custom-loaders.luau) produces no warning for computed module paths or a shadowed `require`.
- [Public functions](invalid/public-functions.luau) highlights names declared or directly assigned as functions on a returned table.
- [Inline public functions](invalid/inline-public-functions.luau) highlights the field name in a returned table literal.
- [Public exceptions](valid/public-exceptions.luau) accepts the constructor, metamethod convention, and PascalCase.
- [Re-exported table](review/reexported-table.luau) produces no finding because another module owns the public API.
- [Invalid variable names](invalid/variable-names.luau) highlights an underscore-prefixed local and a mixed-case scalar constant.
- [Valid variable names](valid/variable-names.luau) accepts the ignored binding, both constant conventions, and numeric separators.
- [Computed constant](review/computed-constant.luau) needs context to determine the value's role.
- [Module identity](invalid/module-identity.luau) reports a lowercase binding when a returned table owns a declared function.
- [Generic state module](invalid/generic-state-module.luau) requires a name that identifies the domain.
- [Returned record](review/returned-record.luau) produces no naming finding because its role as a module identity is unclear.
- [Stable local constant](invalid/stable-local-constant.luau) highlights `local` when a top-level literal constant never changes.
- [Mutated local](review/mutated-local.luau) keeps `local` because a nested closure reassigns it.
- [Invalid scalar local names](invalid/scalar-local-names.luau) highlights PascalCase and snake_case local names.
- [Valid scalar local names](valid/scalar-local-names.luau) accepts camelCase at module and function scope.
