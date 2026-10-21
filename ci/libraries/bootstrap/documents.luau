-- ci/libraries/bootstrap/documents.luau
--!strict

local Documents = {}

--# Modules

local Fs = require("@lune/fs")
local Canonical = require("./canonical")
local Json = require("./json")

--# Types

export type Value = Canonical.Value

--# Functions

function Documents.Read(path: string): Canonical.Value
	return Canonical.Decode(Fs.readFile(path))
end

function Documents.Write(path: string, value: Canonical.Value)
	local parent = path:match("^(.*)/[^/]+$")
	if parent then
		Fs.writeDir(parent)
	end
	Fs.writeFile(path, assert(Canonical.Encode(value)) .. "\n")
end

function Documents.Get(value: Canonical.Value, key: string): Canonical.Value?
	local field = Json.Fields(value)[key]
	-- Valid UTF-8 strings have the same canonical UTF-16 representation. Keep
	-- unmatched surrogates in the lossless representation rather than replacing them.
	if type(field) == "table" and field.kind == "string" then
		return Canonical.Text(field) or field
	end
	return field
end

function Documents.Required(value: Canonical.Value, key: string): Canonical.Value
	return (assert(Documents.Get(value, key), "missing field: " .. key))
end

function Documents.Text(value: Canonical.Value, key: string): string
	return Json.String(Documents.Get(value, key))
end

function Documents.Number(value: Canonical.Value, key: string): number
	return Json.Number(Documents.Get(value, key))
end

function Documents.Items(value: Canonical.Value, key: string): { Canonical.Value }
	return Json.Array(Documents.Get(value, key))
end

function Documents.Set(value: Canonical.Value, key: string, field: Canonical.Value?): Canonical.Object
	return Json.Replace(value, key, field)
end

function Documents.Equal(a: Canonical.Value?, b: Canonical.Value?): boolean
	return a ~= nil and b ~= nil and Canonical.Encode(a) == Canonical.Encode(b)
end

function Documents.From(value: unknown): Canonical.Value
	-- For newly constructed unsigned data only. Read authenticated JSON as bytes.
	return Canonical.FromLune(value)
end

function Documents.Plain(value: Canonical.Value): unknown
	if type(value) ~= "table" then
		return value
	end
	if value.kind == "null" or value.kind == "missing" then
		return nil
	end
	if value.kind == "string" then
		return Canonical.Text(value)
	end
	local result: { [string | number]: unknown } = {}
	if value.kind == "array" then
		for index, child in value.items do
			result[index] = Documents.Plain(child)
		end
	else
		for key, child in Json.Fields(value) do
			result[key] = Documents.Plain(child)
		end
	end
	return result
end

return Documents
