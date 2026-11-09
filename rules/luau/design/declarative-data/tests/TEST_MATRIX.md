# Declarative-data acceptance matrix

The separate test system executes each fixture. Run the fixture suite from the repository root with `node dependencies/packages/core/dependencyLoader/index.ts --exec luau.lute run rules/luau/design/declarative-data/tests/run.luau`. Production validation never reads this directory.

| Case | Expected | Fixture |
| --- | --- | --- |
| Lowercase static boolean map | Violation | [lowercase-boolean-map](invalid/lowercase-boolean-map.luau) |
| Uppercase static boolean map | Violation | [uppercase-boolean-map](invalid/uppercase-boolean-map.luau) |
| Single-field static table | Violation | [single-field](invalid/single-field.luau) |
| Static string/number catalog | Violation | [static-catalog](invalid/static-catalog.luau) |
| Nested static configuration returned from module | Violation | [nested-module-table](invalid/nested-module-table.luau) |
| Literal table containing an inline function | Valid | [inline-function](valid/inline-function.luau) |
| Module table with declared functions | Valid | [method-api](valid/method-api.luau) |
| Table populated and removed from at runtime | Valid | [runtime-mutation](valid/runtime-mutation.luau) |
| Collection built from computed runtime values | Valid | [computed-collection](valid/computed-collection.luau) |
| Table initialized using a runtime expression | Valid | [computed-initializer](valid/computed-initializer.luau) |
| Empty scratch table used during computation | Valid | [scratch-table](valid/scratch-table.luau) |
| Static table declared with `const` | Violation | [static-const](invalid/static-const.luau) |
| Static table created via one-time field assignments | Violation | [staged-initialization](invalid/staged-initialization.luau) |
| Static table created with bracketed assignments | Violation | [staged-index-assignment](invalid/staged-index-assignment.luau) |
| Function assigned to a previously static table | Valid | [function-assignment](valid/function-assignment.luau) |
| Table mutated using library operations | Valid | [table-operations](valid/table-operations.luau) |
| Static table mutated through a local alias during execution | Valid | [alias-mutation](valid/alias-mutation.luau) |
| Static table populated once through a local alias | Violation | [staged-alias](invalid/staged-alias.luau) |
| Nonserializable runtime engine value | Review, no automatic warning | [runtime-engine-value](review/runtime-engine-value.luau) |
| Static table passed to an opaque external callback | Review, no automatic warning | [external-mutation](review/external-mutation.luau) |
| Shadowed or similar identifiers | Valid | [shadowed-names](valid/shadowed-names.luau) |

`review` means human judgment is required; an uncertain case must not become a fabricated violation. A test must not pass solely because a validator recognizes one capitalization pattern or field count.

- [Literal interpolation](invalid/literal-interpolation.luau) is static because every interpolated value is a primitive literal.
- [Runtime interpolation](valid/runtime-interpolation.luau) keeps an interpolated runtime value outside the check.
