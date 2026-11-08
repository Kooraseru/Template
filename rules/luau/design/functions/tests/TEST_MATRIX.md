# Function ownership fixtures

- [Global helper](invalid/global-helper.luau) reports the global name.
- [Forward local](valid/forward-local.luau) passes because the function resolves to an existing local binding.
- [Runtime callback](review/runtime-callback.luau) produces no finding. Entry-point callbacks depend on runtime ownership.
- [Nested global helper](invalid/nested-global-helper.luau) reports an accidental global declaration inside a returned function.
- [Nested local helper](valid/nested-local-helper.luau) accepts a nested declaration that resolves to an existing local.
