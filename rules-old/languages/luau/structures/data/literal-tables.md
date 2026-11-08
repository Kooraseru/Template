# Literal tables

Literal tables are a Luau language feature, not a universal module structure. Use them where their role is executable, transient, structural, or runtime-owned.

## Prefer external data for static catalogs

Avoid a module that only returns a fixed record or lookup:

```luau
return {
	spacing = { small = 4, medium = 8 },
	colors = { primary = "#ffffff" },
}
```

Store this ordinary data in a file such as `theme.toml` or `theme.json`, load it through the owning adapter, and validate its shape.

## Keep executable tables in Luau

```luau
const Formatter = {}

function Formatter.FormatName(name: string): string
	return string.upper(name)
end

return Formatter
```

Likewise, a dynamically populated registry or accumulator belongs in Luau because its values and lifetime are determined by execution.

An inline table passed to a function is not automatically a forbidden data module. Judge the table's responsibility and lifetime; the [declarative-data rule](../../../../../rules/luau/design/declarative-data/README.md) describes the intent and checker limitations.
