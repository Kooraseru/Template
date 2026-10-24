-- ci/utilities/canonical.luau
--!strict

local Canonical = {}

--# Modules

local Serde = require("@lune/serde")
local Native = require("./native")

--# Types

export type Units = { kind: "string", units: { number } }
export type Text = string | Units
export type Marker = { read kind: "null" | "missing" }
export type Object = { kind: "object", entries: { { key: Text, value: Value } } }
export type Array = { kind: "array", items: { Value }, length: number }
export type Value = boolean | number | string | Units | Marker | Object | Array

--# Constants

local NULL_VALUE: Marker = { kind = "null" }
local MISSING_VALUE: Marker = { kind = "missing" }

table.freeze(NULL_VALUE)
table.freeze(MISSING_VALUE)

Canonical.Null = NULL_VALUE
Canonical.Missing = MISSING_VALUE

--# Helpers

local function appendCodepoint(units: { number }, point: number)
	if point <= 65535 then
		table.insert(units, point)
	else
		local offset = point - 65536
		table.insert(units, 55296 + math.floor(offset / 1024))
		table.insert(units, 56320 + offset % 1024)
	end
end

local function textUnits(text: Text): { number }
	if type(text) == "table" then
		return text.units
	end

	local units = {}

	for _, point in utf8.codes(text) do
		appendCodepoint(units, point)
	end

	return units
end

local function quote(text: Text): string
	local units = textUnits(text)
	local output = { '"' }
	local index = 1
	local escapes = { [8] = "\\b", [9] = "\\t", [10] = "\\n", [12] = "\\f", [13] = "\\r", [34] = '\\"', [92] = "\\\\" }

	while index <= #units do
		local unit = units[index]
		assert(unit >= 0 and unit <= 65535 and unit % 1 == 0, "invalid UTF16 code unit")

		if escapes[unit] then
			table.insert(output, escapes[unit])
		elseif unit < 32 then
			table.insert(output, string.format("\\u%04x", unit))
		elseif
			unit >= 55296
			and unit <= 56319
			and units[index + 1]
			and units[index + 1] >= 56320
			and units[index + 1] <= 57343
		then
			table.insert(output, utf8.char(65536 + (unit - 55296) * 1024 + units[index + 1] - 56320))
			index += 1
		elseif unit >= 55296 and unit <= 57343 then
			table.insert(output, string.format("\\u%04x", unit))
		else
			table.insert(output, utf8.char(unit))
		end

		index += 1
	end

	table.insert(output, '"')

	return table.concat(output)
end

local function integerKey(key: Text): number?
	local units = textUnits(key)
	local digits = {}

	for _, unit in units do
		if unit < 48 or unit > 57 then
			return nil
		end

		table.insert(digits, string.char(unit))
	end

	local text = table.concat(digits)

	if text == "" or (#text > 1 and text:sub(1, 1) == "0") then
		return nil
	end

	local number = tonumber(text)

	return if number and number < 4294967295 then number else nil
end

local function keyBefore(left: Text, right: Text): boolean
	local leftIndex, rightIndex = integerKey(left), integerKey(right)

	if leftIndex and rightIndex then
		return leftIndex < rightIndex
	elseif leftIndex then
		return true
	elseif rightIndex then
		return false
	end

	local a, b = textUnits(left), textUnits(right)

	for index = 1, math.min(#a, #b) do
		if a[index] ~= b[index] then
			return a[index] < b[index]
		end
	end

	return #a < #b
end

local function missing(value: Value?): boolean
	return value == nil or (type(value) == "table" and value.kind == "missing")
end

local function collectNumbers(value: Value, values: { number }, seen: { [number]: boolean })
	if type(value) == "number" then
		if value == value and math.abs(value) ~= math.huge and not seen[value] then
			seen[value] = true
			table.insert(values, value)
		end
	elseif type(value) == "table" then
		if value.kind == "object" then
			for _, entry in value.entries do
				collectNumbers(entry.value, values, seen)
			end
		elseif value.kind == "array" then
			for _, child in value.items do
				collectNumbers(child, values, seen)
			end
		end
	end
end

local function render(value: Value, numbers: { [number]: string }): string?
	if type(value) == "string" then
		return quote(value)
	elseif type(value) == "boolean" then
		return tostring(value)
	elseif type(value) == "number" then
		return if value ~= value or math.abs(value) == math.huge
			then "null"
			else assert(numbers[value], "unformatted number")
	elseif value.kind == "null" then
		return "null"
	elseif value.kind == "missing" then
		return nil
	elseif value.kind == "string" then
		return quote(value)
	elseif value.kind == "array" then
		local output = {}

		for index = 1, value.length do
			local item = value.items[index]
			table.insert(output, if missing(item) then "null" else render(item, numbers) or "null")
		end

		return "[" .. table.concat(output, ",") .. "]"
	else
		-- Object.fromEntries overwrites duplicate names before the replacer's next visit.
		local fields: { [string]: { key: Text, value: Value } } = {}

		for _, entry in value.entries do
			fields[quote(entry.key)] = entry
		end

		local entries = {}

		for _, entry in fields do
			if not missing(entry.value) then
				table.insert(entries, entry)
			end
		end

		table.sort(entries, function(left: { key: Text, value: Value }, right: { key: Text, value: Value })
			return keyBefore(left.key, right.key)
		end)
		local output = {}

		for _, entry in entries do
			table.insert(output, quote(entry.key) .. ":" .. assert(render(entry.value, numbers)))
		end

		return "{" .. table.concat(output, ",") .. "}"
	end
end

--# Functions

function Canonical.Text(text: Text): string?
	if type(text) == "string" then
		return text
	end

	local output = {}
	local index = 1

	while index <= #text.units do
		local unit = text.units[index]

		if unit >= 55296 and unit <= 56319 then
			local nextUnit = text.units[index + 1]

			if not nextUnit or nextUnit < 56320 or nextUnit > 57343 then
				return nil
			end

			table.insert(output, utf8.char(65536 + (unit - 55296) * 1024 + nextUnit - 56320))
			index += 2
		elseif unit >= 56320 and unit <= 57343 then
			return nil
		else
			table.insert(output, utf8.char(unit))
			index += 1
		end
	end

	return table.concat(output)
end

function Canonical.Object(fields: { [string]: Value }): Object
	local entries = {}

	for key, value in fields do
		table.insert(entries, { key = key, value = value })
	end

	return { kind = "object", entries = entries }
end

function Canonical.Array(items: { Value }, length: number?): Array
	return { kind = "array", items = items, length = length or #items }
end

function Canonical.Encode(value: Value): string?
	local values = {}
	collectNumbers(value, values, {})
	local formatted = Native.Numbers(values)
	local numbers = {}

	for index, number in values do
		numbers[number] = formatted[index]
	end

	return render(value, numbers)
end

function Canonical.Hash(value: Value): string
	local bytes = assert(Canonical.Encode(value), "missing root has no canonical bytes")

	return Serde.hash("sha256", bytes)
end

-- This parser preserves nulls, empty arrays/objects and UTF16 surrogate escapes.
-- Decoding into ordinary Luau tables first would erase those distinctions.
function Canonical.Decode(source: string): Value
	local cursor = 1

	local function whitespace()
		while source:sub(cursor, cursor):match("[ \t\r\n]") do
			cursor += 1
		end
	end

	local function parseString(): Units
		assert(source:sub(cursor, cursor) == '"', "expected JSON string")
		cursor += 1
		local units = {}
		local escapes: { [string]: number } =
			{ ['"'] = 34, ["\\"] = 92, ["/"] = 47, b = 8, f = 12, n = 10, r = 13, t = 9 }

		while cursor <= #source do
			local character = source:sub(cursor, cursor)

			if character == '"' then
				cursor += 1
				return { kind = "string", units = units }
			elseif character == "\\" then
				local escaped = source:sub(cursor + 1, cursor + 1)

				if escaped == "u" then
					local hex = source:sub(cursor + 2, cursor + 5)
					assert(#hex == 4 and hex:match("^%x+$"), "invalid JSON unicode escape")
					table.insert(units, assert(tonumber(hex, 16)))
					cursor += 6
				else
					table.insert(units, (assert(escapes[escaped], "invalid JSON escape")))
					cursor += 2
				end
			else
				assert(character:byte() >= 32, "unescaped JSON control character")
				local point = utf8.codepoint(source, cursor)
				appendCodepoint(units, point)
				cursor += if point < 128 then 1 elseif point < 2048 then 2 elseif point < 65536 then 3 else 4
			end
		end

		error("unterminated JSON string")
	end

	local function parse(): Value
		whitespace()
		local character = source:sub(cursor, cursor)

		if character == '"' then
			return parseString()
		elseif character == "{" then
			cursor += 1
			whitespace()
			local entries: { { key: Text, value: Value } } = {}

			if source:sub(cursor, cursor) ~= "}" then
				while true do
					whitespace()
					local key = parseString()
					whitespace()
					assert(source:sub(cursor, cursor) == ":", "missing JSON colon")
					cursor += 1
					local entry: { key: Text, value: Value } = { key = key, value = parse() }
					table.insert(entries, entry)
					whitespace()

					if source:sub(cursor, cursor) ~= "," then
						break
					end

					cursor += 1
				end
			end

			assert(source:sub(cursor, cursor) == "}", "unterminated JSON object")
			cursor += 1
			return { kind = "object", entries = entries }
		elseif character == "[" then
			cursor += 1
			whitespace()
			local items = {}

			if source:sub(cursor, cursor) ~= "]" then
				while true do
					table.insert(items, parse())
					whitespace()

					if source:sub(cursor, cursor) ~= "," then
						break
					end

					cursor += 1
				end
			end

			assert(source:sub(cursor, cursor) == "]", "unterminated JSON array")
			cursor += 1
			return Canonical.Array(items)
		end

		local literals: { [string]: Value } = { ["true"] = true, ["false"] = false, ["null"] = Canonical.Null }

		for token, value in literals do
			if source:sub(cursor, cursor + #token - 1) == token then
				cursor += #token
				return value
			end
		end

		local start = cursor

		if character == "-" then
			cursor += 1
		end

		if source:sub(cursor, cursor) == "0" then
			cursor += 1
		else
			assert(source:sub(cursor, cursor):match("[1-9]"), "invalid JSON value")

			repeat
				cursor += 1
			until not source:sub(cursor, cursor):match("%d")
		end

		if source:sub(cursor, cursor) == "." then
			cursor += 1
			assert(source:sub(cursor, cursor):match("%d"), "missing JSON fractional digits")

			repeat
				cursor += 1
			until not source:sub(cursor, cursor):match("%d")
		end

		if source:sub(cursor, cursor):match("[eE]") then
			cursor += 1

			if source:sub(cursor, cursor):match("[+-]") then
				cursor += 1
			end

			assert(source:sub(cursor, cursor):match("%d"), "missing JSON exponent digits")

			repeat
				cursor += 1
			until not source:sub(cursor, cursor):match("%d")
		end

		return (assert(tonumber(source:sub(start, cursor - 1)), "invalid JSON number"))
	end

	local value = parse()
	whitespace()
	assert(cursor > #source, "trailing JSON input")

	return value
end

function Canonical.FromLune(raw: unknown): Value
	return Canonical.Decode(Serde.encode("json", raw))
end

return Canonical
