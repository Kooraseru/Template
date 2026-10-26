# Luau control flow: “if not, not if”

The mnemonic means: **handle what prevents progress first**, then write the successful operation without burying it in positive-condition nesting.

```luau
local character = player.Character
if not character then
    return
end

local rootPart = character:FindFirstChild("HumanoidRootPart")
if not rootPart then
    return
end

moveCharacter(rootPart)
```

Use `if not enabled then continue end` in loops when it makes the active path obvious.

## Assertions and error boundaries

Assert only when absolutely necessary; do not throw asserts across general control flow.

The design eliminates unexpected breakpoints through strict-as-possible static guarantees and preflight checks:

- **Confine to protected calls:** Only use `assert` within `pcall` or `xpcall` boundaries where errors are caught, handled, or formatted into structured reports. Prefer `xpcall` when its error handler adds useful context or normalization.
- **No scattershot breakpoints:** Unhandled asserts dirty module flow and abort execution prematurely. Do not use `assert` as a shortcut for control flow.
- **Prefer guards and explicit returns:** When an invariant or input is absent outside a protected boundary, handle it with an early guard clause, explicit error return, or typed fallback.

Do not mechanically negate every `if`. Positive branches are useful for purposeful alternatives, simple optional behavior, and mutually exclusive cases. Prefer clear dispatch, one responsibility per branch, and delegation to deeply nested decisions. Avoid expression chains that become boolean puzzles.

`continue` only skips the loop iteration; `return` exits the current function. A guard must make its scope and consequence unambiguous. Protect cleanup/transaction invariants before returning early.

See [expressions](expressions.md), [functions](functions.md), and [Rust's corresponding rule](../../rust/language/control-flow.md).
