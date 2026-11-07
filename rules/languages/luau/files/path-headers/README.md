# Luau path headers

Start hand-written Luau files under source/, .github/ci/, and dependencies/packages/ with a comment naming their workspace-relative path. Use forward slashes, for example `-- source/hosts/windows-amd/init.luau`. Either LF or CRLF is accepted.

The validator reports an error at line 1, column 1 for a missing or mismatched header. Generated and vendored code, examples, and tests are excluded. Luau tooling owns type-checking directives.
