-- ci/libraries/bootstrap/json.luau
--!strict

local Json = {}

--# Modules

local Canonical = require("./canonical")

--# Functions

function Json.Object(value: Canonical.Value?): Canonical.Object
	assert(type(value) == "table" and value.kind == "object", "expected JSON object")

	return value
end

function Json.Fields(value: Canonical.Value?): { [string]: Canonical.Value }
	local fields = {}

	for _, entry in Json.Object(value).entries do
		local key = Canonical.Text(entry.key)

		if key then
			fields[key] = entry.value
		end
	end

	return fields
end

function Json.Array(value: Canonical.Value?): { Canonical.Value }
	assert(type(value) == "table" and value.kind == "array", "expected JSON array")
	assert(value.length == #value.items, "sparse JSON array")

	return value.items
end

function Json.String(value: Canonical.Value?): string
	if type(value) == "string" then
		return value
	end

	assert(type(value) == "table" and value.kind == "string", "expected JSON string")

	return (assert(Canonical.Text(value), "invalid Unicode in required string"))
end

function Json.Number(value: Canonical.Value?): number
	assert(type(value) == "number", "expected JSON number")

	return value
end

function Json.Truthy(value: Canonical.Value?): boolean
	if value == nil or value == false or value == "" or value == 0 then
		return false
	end

	if type(value) == "number" then
		return value == value
	elseif type(value) == "table" then
		return value.kind ~= "null" and value.kind ~= "missing"
	end

	return true
end

function Json.Replace(value: Canonical.Value, key: string, selected: Canonical.Value?): Canonical.Object
	local entries: { { key: Canonical.Text, value: Canonical.Value } } = {}

	for _, entry in Json.Object(value).entries do
		if Canonical.Text(entry.key) ~= key then
			table.insert(entries, entry)
		end
	end

	if selected ~= nil then
		local entry: { key: Canonical.Text, value: Canonical.Value } = { key = key, value = selected }
		table.insert(entries, entry)
	end

	return { kind = "object", entries = entries }
end

function Json.Data(value: Canonical.Value): unknown
	if type(value) ~= "table" then
		return value
	elseif value.kind == "string" then
		return Canonical.Text(value) or value
	elseif value.kind == "null" or value.kind == "missing" then
		return value
	elseif value.kind == "array" then
		local items = {}

		for _, item in value.items do
			table.insert(items, Json.Data(item))
		end

		return items
	else
		local fields = {}

		for key, child in Json.Fields(value) do
			fields[key] = Json.Data(child)
		end

		return fields
	end
end

return Json
