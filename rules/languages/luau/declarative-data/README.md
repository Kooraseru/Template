# Declarative data belongs outside Luau

Luau is the execution and coordination language. Do not use a Luau table merely to encode configuration, catalogs, static descriptors, or other data that could be represented faithfully in a data format such as JSON or TOML.

This rule is about a table's purpose and behavior, not its name, capitalization, number of fields, or whether values happen to be booleans.

## Allowed

Tables that expose functions or other executable behavior:

```luau
const Metrics = {}

function Metrics.Record(name: string): ()
	print(name)
end

return Metrics
```

Tables that own runtime state and are demonstrably updated:

```luau
const active = {}

local function Register(id: string): ()
	active[id] = true
end

local function Unregister(id: string): ()
	active[id] = nil
end
```

Tables used as temporary, runtime-created collections are also reasonable when their contents depend on execution. Do not require a function field in a table that is genuinely mutable state.

## Disallowed

A literal data table returned as a module:

```luau
return {
	name = "Example",
	version = "1.0.0",
	enabled = true,
}
```

A one-time initialized lookup that is never meaningfully modified:

```luau
const COLORS = {
	red = true,
	green = true,
	blue = true,
}

return COLORS
```

Changing the binding from `local` to `const`, renaming the table, or splitting the literal across assignments does not change its declarative purpose. Staged one-time initialization should not be mistaken for a runtime-owned collection.

## Data boundary

Place ordinary static data in an external source file with an explicit schema where one is useful. Load and validate it at the owning boundary; keep the Luau adapter small and typed. Do not move runtime-only objects, functions, engine values, or dynamically computed state into JSON/TOML merely to satisfy a mechanical pattern.

When a value must be constructed in Luau because its representation cannot survive a data format, document that runtime constraint. Narrow, non-serializable engine descriptors are an exception, not permission to store every ordinary configuration table in code.

## Checker contract

The checker should recognize function-bearing tables and observable mutation, including direct index assignments and relevant `table.insert`/`table.remove`/`table.clear` calls. It must not flag a table because of identifier capitalization or a fixed count of fields.

Track simple local aliases as references to the same table, not copies. A runtime mutation through an unchanged alias is observable behavior; a one-time static assignment through that alias remains declarative data. Neither changes classification merely by using another variable name.

Static analysis cannot always prove what a callback or another module does to a table. Do not equate an opaque escape with evidence of immutability. Use precise diagnostics only for supported cases, and document blind spots.

The imported `validation.luau` implementation uses Lute's syntax tree to track lexical table bindings, simple stable aliases, function fields, declared methods, and direct runtime mutations. It conservatively exempts opaque escapes whose effects it cannot establish.

The separate test system owns the [21 acceptance cases](tests/TEST_MATRIX.md). It executes the fixtures independently; the validator never loads `tests/`. Template reports supported violations as errors on workspace source. Review cases remain advisory.
