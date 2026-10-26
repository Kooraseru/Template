--!strict

-- Analyzer-only declaration for the Lune serialization module.
export type Format = "json" | "jsonc" | "toml" | "yaml"

local Serde = {} :: {
	compress: (format: "gzip", bytes: string | buffer) -> string,
	encode: <T>(format: Format, value: T, pretty: boolean?) -> string,
	decode: <T>(format: Format, encoded: string | buffer) -> T,
	hash: (algorithm: "sha256", message: string | buffer) -> string,
}

return Serde
