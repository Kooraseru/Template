# Single-operation Luau modules

The check identifies a standalone module that only wraps one function named exactly like the file. It covers an inline returned table or an empty local table with one dot-style function and an immediate return of that table. A function that uses the module table internally requires review. An existing table API can be part of a caller contract, so this warning offers no automatic edit.

Directory heads, additional exports, and different export names require review. See the [fixture matrix](tests/TEST_MATRIX.md).

A returned record that repeats the module name around a single local or constant function binding is also flagged. A differently named public operation keeps its own contract.

## Function module guidance

A return-function module owns one operation.

Use it when naming the file already names the concept clearly enough. Adding a module table would only repeat the same name around one function.

Required:

- path label and `--!strict`
- returned function

Usually absent:

- module identity table
- exported methods
- constructor
- lifecycle headers

```luau
-- source/app/Clamp.luau
--!strict

return function(value: number, minimum: number, maximum: number): number
	return math.clamp(value, minimum, maximum)
end
```

Why this shape:

- the file has one reason to exist
- the function has no stored state
- there is no public surface to organize beyond the returned callable
- testing can focus on input/output behavior


Returned records use the same check for a bare field or a quoted bracket key spelling the module name. Computed keys stay for review.
