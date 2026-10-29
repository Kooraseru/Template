# Luau Types

This document owns type-safety constraints and allowed uncertainty boundaries.

## Main Rule

Type assertions using `::` are prohibited. They override the type system's
knowledge instead of describing or proving the value's shape. Do not use them
to silence errors, skip validation, or force a metatable instance shape.

Type annotations using `:` are allowed and encouraged. An annotation gives a
value, parameter, field, or return value an explicit type for the type checker
to verify. For example, `local reporter: Reporter` is a type hint; it does not
convert the value. Use annotations to make intended shapes clear, then fix any
errors by establishing that shape in code.

Prefer `const` for local bindings that are assigned once. `const` prevents
rebinding the name; it does not freeze a table's contents. Use `table.freeze`
when the value itself must also be immutable.

The same prohibition applies to `any`: do not introduce or propagate `any` to
avoid describing and checking the real shape.

When a type error appears, resolve it in this order:

1. Improve inference.
2. Improve the API or helper type.
3. Improve the typed lookup surface.
4. Improve the caller's type.
5. Add an explicit structural contract.
6. Move validation to the actual boundary.
7. Use a typed adapter or a validated constructor at the boundary where
   uncertainty actually enters.

Never use `::` or `any`, including at constructors, deserialization
boundaries, or engine APIs. Model incomplete construction with fields-first
initialization, validate raw inputs before creating typed domain values, and
adapt external APIs with explicit structural types and checked functions.

## Lookup Types

Prefer typed lookup surfaces for owned child sets:

```luau
local Settings = {
	Render = require("./Settings/Render"),
	Import = require("./Settings/Import"),
}

export type SettingGroup = keyof<typeof(Settings)>
export type SettingsMap = typeof(Settings)

return Settings
```

If a manifest is unavoidable, preserve exact table shape before extracting ids. Do not widen first:

```luau
local Actions: { [string]: ActionDefinition } = { ... }
```

That destroys the literal key union.

## Values Utility

For a known table shape, a value union is:

```luau
type Values<T> = index<T, keyof<T>>
```

For metatable-sensitive cases, consider `rawkeyof` and `rawget` when inherited `__index` keys should not count.

## Unknown vs Any

Use `unknown` for raw values that must be validated.

`any` is prohibited. Use `unknown` for untrusted values and narrow it with
runtime checks before storing it in domain types. Do not hide `any` behind
aliases, generic parameters, or casts.
