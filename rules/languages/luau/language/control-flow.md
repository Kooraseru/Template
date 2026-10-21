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

Use `if not enabled then continue end` in loops when it makes the active path obvious. Use `assert` or an explicit error return when a missing requirement is a contract violation, not a harmless absence.

Do not mechanically negate every `if`. Positive branches are useful for purposeful alternatives, simple optional behavior, and mutually exclusive cases. Prefer clear dispatch, one responsibility per branch, and delegation to deeply nested decisions. Avoid expression chains that become boolean puzzles.

`continue` only skips the loop iteration; `return` exits the current function. A guard must make its scope and consequence unambiguous. Protect cleanup/transaction invariants before returning early.

See [expressions](expressions.md), [functions](functions.md), and [Rust's corresponding rule](../../rust/language/control-flow.md).
