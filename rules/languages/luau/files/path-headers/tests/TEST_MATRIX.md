# Test matrix

| Fixture | Source context | Expected |
| --- | --- | --- |
| valid/header.luau | source/header.luau with LF or CRLF | No error |
| invalid/missing.luau | source/missing.luau | One error at 1:1 |
| invalid/mismatch.luau | source/mismatch.luau | One error at 1:1 |
| invalid/missing.luau | source/tests/sample.luau | Excluded |

Run `node dependencies/packages/dependencyLoader/index.ts --exec luau.lute run rules/languages/luau/files/path-headers/tests/run.luau` from the repository root.
