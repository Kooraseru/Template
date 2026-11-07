# Luau type-reference acceptance matrix

Template checks these fixtures through the Repository rules stage. Expected violations appear as Rule fixture diagnostics.

| Case | Expected | Fixture |
| --- | --- | --- |
| Explicit structural annotations | Valid | [explicit-types](valid/explicit-types.luau) |
| Runtime identifier named `any` and unrelated text | Valid | [runtime-name](valid/runtime-name.luau) |
| Top-level `any` annotations | Violation | [any-annotations](invalid/any-annotations.luau) |
| Nested `any` annotations | Violation | [nested-any](invalid/nested-any.luau) |

Review [qualified-any](review/qualified-any.luau) separately. A qualified type reference requires knowledge of the exporting module and must produce no finding from this validator.
