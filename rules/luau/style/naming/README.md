# Luau declaration names

Use PascalCase for local and exported Luau type aliases. The check requires an uppercase first letter and alphanumeric characters. Acronyms and digits are accepted. The diagnostic highlights the alias name.

Function and method parameters use camelCase. The bare underscore is accepted for an ignored argument. The diagnostic points at the parameter token.

Named local functions use camelCase, including functions returned directly by a module and bindings initialized with function expressions. The diagnostic highlights the declared name.

Single top-level bindings initialized by a direct global `require` call with a string literal use PascalCase. Dynamic loading and shadowed loaders require review.

Public functions use PascalCase when declared directly on a returned table initialized in the same module or inline in a returned table literal. The constructor `new` and names beginning with the metamethod prefix `__` are exempt. Re-exported and reassigned tables require review.

Direct function assignments and bracket keys containing a literal identifier use the same convention. Computed and non-identifier keys require review.

A stable, locally declared table returned as a module with a directly declared function uses a PascalCase identity name. Generic `State` and `States` names should identify the state domain. A returned record without a function declaration needs review.

Local and constant declarations reject underscore prefixes and allow the bare ignored binding `_`. Direct scalar literal constants accept camelCase or SCREAMING_SNAKE_CASE. Numeric separators are allowed in the literal.

Top-level SCREAMING_SNAKE_CASE scalar literals use `const` when the binding is never reassigned. The warning highlights the `local` keyword. Assignments inside nested closures also count as reassignment.

Ordinary locals initialized with a scalar literal use camelCase. SCREAMING_SNAKE_CASE bindings are left to the constant check. Computed initializers may need context to distinguish a local from a module or service binding.

This check covers declarations. Runtime names and references to types from another module require context and are outside this validator.

See [Luau naming](../../../../rules-old/languages/luau/language/naming.md) and the [fixture matrix](tests/TEST_MATRIX.md).
