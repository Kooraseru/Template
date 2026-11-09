-- dependencies/packages/core/dataFormats/json.luau
--!strict

local Json = require("@std/json")

-- The standard JSON library marks objects internally. Keep that detail inside
-- this module so configuration consumers see ordinary named fields.
local function value(input: unknown): Json.Value
	if input == nil or type(input) == "boolean" or type(input) == "string" or type(input) == "number" then
		return input
	end
	if type(input) ~= "table" then
		error(`Unsupported JSON type: {type(input)}`, 0)
	end
	local items = input :: { [string | number]: unknown }

	if #items > 0 then
		local result: Json.Array = {}
		for key, item in items do
			if type(key) ~= "number" or key % 1 ~= 0 or key < 1 or key > #items then
				error("Invalid JSON array key", 0)
			end
			result[key] = value(item)
		end
		return result
	end

	local result: Json.Object = Json.object({})

	for key, item in items do
		if type(key) ~= "string" then
			error("JSON object keys must be strings", 0)
		end
		result[key] = value(item)
	end
	return result
end

local function encode(input: unknown): string
	return Json.serialize(value(input))
end

local function plain(input: Json.Value): unknown
	if type(input) ~= "table" then
		return input
	end
	local object = Json.asObject(input)

	if object then
		local result: { [string]: unknown } = {}
		for key, item in object do
			if type(key) == "string" then
				result[key] = plain(item)
			end
		end
		return result
	end

	local result: { unknown } = {}
	for _, item in input :: Json.Array do
		table.insert(result, plain(item))
	end
	return result
end

local function decode(input: string): unknown
	return plain(Json.deserialize(input))
end

local function record(input: unknown): { [string]: unknown }
	if type(input) ~= "table" then
		error("Expected a data object", 0)
	end
	local result: { [string]: unknown } = {}
	for key, item in input :: { [unknown]: unknown } do
		if type(key) ~= "string" then
			error("Expected string object keys", 0)
		end
		result[key] = item
	end
	return result
end

local function isNull(input: unknown): boolean
	return input == Json.null
end

return { encode = encode, decode = decode, record = record, isNull = isNull }
