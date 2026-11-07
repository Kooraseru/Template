# Test matrix

| Fixture | Source context | Expected |
| --- | --- | --- |
| valid/header.luau | source/sample.luau with LF or CRLF | No error |
| invalid/missing.luau | source/sample.luau | One error at 1:1 |
| invalid/mismatch.luau | source/sample.luau | One error at 1:1 |
| invalid/missing.luau | source/tests/sample.luau | Excluded |

Run `node dependencies/packages/dependencyLoader/index.ts --exec luau.lute run rules/languages/luau/files/path-headers/tests/run.luau` from the repository root.
