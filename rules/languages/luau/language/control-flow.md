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

Use `assert` when violating a documented invariant must stop execution, especially in tests, initialization, or internal consistency checks. Do not use it as routine input validation or branching logic.

At recoverable boundaries, use an early guard clause, an explicit error result, or a typed fallback. Wrap an operation in `pcall` only when its failure must genuinely be caught and handled, not merely to make an assertion acceptable.

Do not mechanically negate every `if`. Positive branches are useful for purposeful alternatives, simple optional behavior, and mutually exclusive cases. Prefer clear dispatch, one responsibility per branch, and delegation to deeply nested decisions. Avoid expression chains that become boolean puzzles.

`continue` only skips the loop iteration; `return` exits the current function. A guard must make its scope and consequence unambiguous. Protect cleanup/transaction invariants before returning early.

See [expressions](expressions.md), [functions](functions.md), and [Rust's corresponding rule](../../rust/language/control-flow.md).
