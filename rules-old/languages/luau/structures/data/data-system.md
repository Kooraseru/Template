# Data boundaries

Static configuration and other declarative data should live in an appropriate data file, not in a Luau module whose only purpose is returning a literal table. See the [declarative-data rule](../../../../../rules/luau/design/declarative-data/README.md).

Separate four responsibilities:

1. Data source: externally editable JSON, TOML, or another appropriate format.
2. Schema: the allowed fields, types, and domain constraints.
3. Loader: boundary parsing and validation.
4. Runtime: the typed values, methods, and mutable state consumed by the application.

Keep one authoritative source for a fact. Avoid writing the same configuration in both a data file and a Luau table.

A Luau table remains appropriate when it represents runtime state, behavior, a typed API, or values that cannot be faithfully serialized. Construct or validate such values at a clear boundary. Do not convert engine-specific values to strings merely to satisfy a preference for external data.

Use a short module for loading and validating external data when that is genuinely an executable operation; avoid forwarding-only modules.
