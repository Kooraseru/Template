# Luau Functions

This document owns language-wide function guidance.

Function names follow [naming](../../style/naming/guidance.md). Document nontrivial public contracts using [Luau function documentation](../../style/function-documentation/README.md).

Project-owned receiver methods follow the selected structure. OOP receiver methods are owned by [objects](../objects/README.md).

Prefer local helper functions for private behavior. Do not create table-private methods just to simulate privacy.

## Basic Helper

```luau
local function normalizeText(text: string?): string
	return text or ""
end
```

## Return Function

Use a return-function module when the file owns one operation:

```luau
return function(value: number, minimum: number, maximum: number): number
	return math.clamp(value, minimum, maximum)
end
```

Use explicit return values for real failures; a silent `return` is not an error strategy.

See [the validator](README.md) for the enforced subset.
