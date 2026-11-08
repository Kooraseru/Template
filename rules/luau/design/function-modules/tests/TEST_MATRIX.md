# Single-operation module fixtures

- [Repeated name](invalid/repeated-name/Clamp.luau) reports the entire wrapper table.
- [Named wrapper](invalid/named-wrapper/Clamp.luau) reports a matching table declaration, function, and return.
- [Recursive wrapper](review/recursive-wrapper/Clamp.luau) produces no finding because the implementation references the module identity.
- [Direct function](valid/direct-function/Clamp.luau) passes.
- [Shared Run interface](review/shared-run-interface/Clamp.luau) produces no finding. A shared consumer may require the table shape.

The module file is named `Clamp.luau` in each fixture so the validator exercises the real module-name context without a separate path override.

- [Bound wrapper](invalid/bound-wrapper/Clamp.luau) reports a same-name field that forwards a local function.
- [Named operation](valid/named-operation/Clamp.luau) preserves a distinct public operation name.
