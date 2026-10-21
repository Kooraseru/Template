# Luau Functions

This document owns language-wide function guidance.

Function names follow [naming](naming.md).

Project-owned receiver methods follow the selected structure. OOP receiver methods are owned by [objects](../structures/oop/objects.md).

Prefer local helper functions for private behavior. Do not create table-private
methods just to simulate privacy.

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

Prefer [early guard clauses](control-flow.md) to nested positive conditions when the function cannot meaningfully proceed. Use explicit return values for real failures; a silent `return` is not an error strategy.
