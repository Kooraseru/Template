# Guard-first branches fixtures

- [Invalid](invalid/example.luau) produces one finding across the construct.
- [Valid](valid/example.luau) passes.
- [Review](review/example.luau) produces no finding. Moving a local declaration can change scope. Review the larger branch manually.
- [Loop break](invalid/loop-break.luau) reports the branch with an assignment and a call opposite a loop exit.
- [Optional operations](valid/optional-operations.luau) passes because there is no early-exit fallback.
- [Protected assertion](invalid/protected-assertion.luau) highlights the entire call wrapping the built-in assertion.
- [Invariant assertion](valid/invariant-assertion.luau) accepts a direct assertion.
- [Shadowed assertion](review/shadowed-assertion.luau) produces no finding because the callable is locally defined.
- [Redundant boolean branches](invalid/redundant-boolean-branches.luau) reports a comparison wrapped in a boolean conditional and a negation expressed as branches.
- [Truthiness conversion](review/truthiness-conversion.luau) produces no warning because the condition itself is not a boolean comparison.
