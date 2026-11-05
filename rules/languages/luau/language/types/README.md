# Executable Type Safety Check

The colocated `check.luau` rejects the broad `any` type in Luau annotations.
Use `unknown` for unvalidated values, or describe the actual structure in the
type system. Comments and string literals do not count as annotations.

`tests/valid.luau` and `tests/invalid.luau` are checked by the Lune fixture
runner. The workspace checker also scans Luau source so the diagnostic appears
without opening the affected file.
