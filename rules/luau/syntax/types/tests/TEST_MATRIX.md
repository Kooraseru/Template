# Luau type-reference acceptance matrix

Template checks these fixtures through the Repository rules stage. Expected violations appear as Rule fixture diagnostics.

| Case | Expected | Fixture |
| --- | --- | --- |
| Explicit structural annotations | Valid | [explicit-types](valid/explicit-types.luau) |
| Runtime identifier named `any` and unrelated text | Valid | [runtime-name](valid/runtime-name.luau) |
| Top-level `any` annotations | Violation | [any-annotations](invalid/any-annotations.luau) |
| Nested `any` annotations | Violation | [nested-any](invalid/nested-any.luau) |
| Repeated assertion through parentheses | Violation | [repeated-assertion](invalid/repeated-assertion.luau) |
| Repeated module-qualified assertion | Violation | [repeated-qualified-assertion](invalid/repeated-qualified-assertion.luau) |
| Matching name from different modules | Review | [different-qualified-assertions](review/different-qualified-assertions.luau) |
| Single assertion after boundary validation | Valid | [validated-boundary](valid/validated-boundary.luau) |
| Different assertions during a boundary conversion | Review | [boundary-conversion](review/boundary-conversion.luau) |

Review [qualified-any](review/qualified-any.luau) separately. A qualified type reference requires knowledge of the exporting module and must produce no finding from this validator.

- [Repeated structural assertions](invalid/repeated-structural-assertion.luau) reports matching generic and table annotations.
- [Different structural assertions](review/different-structural-assertions.luau) leaves a changed generic argument for review.
