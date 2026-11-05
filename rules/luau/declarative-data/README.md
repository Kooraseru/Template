

# Data Table Structure

Data table modules are JSON-like Luau modules.

They return a literal table directly:

```luau
return {
	name = "Example",
	version = "1.0.0",
}
```

Use this structure when the module's main job is to expose declarative values,
configuration, descriptors, fixtures, or simple lookup tables.

The point is that callers read the module as a value, not as an API surface. The
file should answer:

```text
What data is declared here?
```

Functions are allowed when they are values inside the returned data shape, but
the module should still read as data first.

Do not turn a data table into a procedural module just because one field is a
function.

Use another structure when the file needs:

- a named module identity table
- private mutable module state
- constructor behavior
- instance identity
- staged setup before return

Why this shape:

- the returned value is the product
- field names carry the meaning
- there is no lifecycle, hidden state, or public command surface
- generated or fixture-like data stays easy to inspect


# Literal Data Tables

Prefer a direct returned table when the module does not need setup:

```luau
-- source/app/Theme/Tokens.luau
--!strict

return {
	spacing = {
		small = 4,
		medium = 8,
		large = 12,
	},

	color = {
		text = Color3.fromRGB(235, 235, 235),
		panel = Color3.fromRGB(24, 26, 30),
	},
}
```

Keep the table readable as a value.

Avoid adding a local module table only to immediately return it:

```luau
local Tokens = {}

Tokens.spacing = {
	small = 4,
}

return Tokens
```

That shape implies procedural construction. If the module is just data, return
the data.

## Function Values

Function values are allowed when they are part of the declared shape:

```luau
-- source/app/Theme/Scale.luau
--!strict

const base = 8

return {
	base = base,

	step = function(index: number): number
		return index * base
	end,
}
```

If functions become the main point of the module, use a procedural table module
or function module instead.
