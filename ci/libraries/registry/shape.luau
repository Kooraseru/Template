-- libraries/registry/shape.luau
--!strict

local Shape = {}

--# Types

export type Object = { [string]: unknown }

--# Functions

function Shape.Object(value: unknown, fields: { string }): Object
	assert(type(value) == "table", "expected an object")
	local result: Object = {}

	for key, child in value do
		assert(type(key) == "string" and table.find(fields, key), "unexpected field: " .. tostring(key))
		result[key] = child
	end

	return result
end

function Shape.Text(value: unknown, label: string): string
	assert(type(value) == "string" and value:match("%S"), "expected nonempty " .. label)
	assert(not value:find("%c"), "control character in " .. label)

	return value
end

function Shape.Sequence(value: unknown): { unknown }
	assert(type(value) == "table", "expected an array")
	local entries = value :: { [unknown]: unknown }
	local result: { unknown } = {}
	local count = 0

	for key in value do
		assert(type(key) == "number" and key >= 1 and key % 1 == 0, "expected an array index")
		count += 1
	end

	for index = 1, count do
		local item = entries[index]
		assert(item ~= nil, "sparse array")
		table.insert(result, item)
	end

	return result
end

function Shape.Strings(value: unknown, label: string): { string }
	local result: { string } = {}
	local seen: { [string]: boolean } = {}

	for _, item in Shape.Sequence(value) do
		local text = Shape.Text(item, label)
		assert(not seen[text], "duplicate " .. label .. ": " .. text)
		seen[text] = true
		table.insert(result, text)
	end

	return result
end

function Shape.Relative(value: unknown): string
	local path = Shape.Text(value, "relative path")
	assert(not path:find("[\\:%z]") and path:sub(1, 1) ~= "/", "invalid relative path: " .. path)

	for _, part in path:split("/") do
		assert(part ~= "" and part ~= "." and part ~= "..", "invalid path segment: " .. path)
	end

	return path
end

return Shape
