# Luau Expressions

This document owns language-wide expression guidance.

Keep expressions boring when they carry policy, ownership, validation, or
mutation. Prefer named helpers or intermediate locals when an expression becomes
hard to scan.

Use direct expressions for simple value normalization:

```luau
local text = input.Text or ""
```

Use explicit branches when the nil case, validation failure, or side effect
matters:

```luau
if input.Text == nil then
	return nil
end
```

## Guard-first decisions

Apply [“if not, not if”](control-flow.md) when handling an absent or invalid precondition keeps the main path flat. Do not replace useful `if` branches with confusing negations or boolean expression puzzles merely for syntactic consistency.
