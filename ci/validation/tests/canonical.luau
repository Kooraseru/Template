-- validation/tests/canonical.luau
--!strict

local CanonicalTests = {}

--# Modules

local Fs = require("@lune/fs")
local Serde = require("@lune/serde")
local Rules = require("../../libraries/registry/rules")
local Canonical = require("../../libraries/bootstrap/canonical")

--# Helpers

local function materialize(raw: unknown): Canonical.Value
	local input = Rules.Entries(raw)

	if input.kind == "missing" or input.kind == "hole" then
		return Canonical.Missing
	elseif input.kind == "null" then
		return Canonical.Null
	elseif input.kind == "boolean" then
		assert(type(input.value) == "boolean", "invalid boolean fixture")
		return input.value
	elseif input.kind == "number" then
		assert(type(input.text) == "string", "invalid number fixture")

		if input.text == "NaN" then
			return 0 / 0
		elseif input.text == "Infinity" then
			return math.huge
		elseif input.text == "-Infinity" then
			return -math.huge
		end

		return (assert(tonumber(input.text), "invalid numeric fixture text"))
	elseif input.kind == "string" then
		if input.units then
			local units = {}

			for _, value in Rules.Array(input.units) do
				assert(type(value) == "number", "invalid UTF16 fixture")
				table.insert(units, value)
			end

			return { kind = "string", units = units }
		end

		assert(type(input.value) == "string", "invalid string fixture")
		return input.value
	elseif input.kind == "array" then
		local items = {}

		for _, child in Rules.Array(input.items) do
			table.insert(items, materialize(child))
		end

		return Canonical.Array(items)
	elseif input.kind == "object" then
		local fields = {}

		for _, rawEntry in Rules.Array(input.entries) do
			local entry = Rules.Array(rawEntry)
			local key = entry[1]
			assert(type(key) == "string", "invalid object fixture key")
			fields[key] = materialize(entry[2])
		end

		return Canonical.Object(fields)
	end

	error("unknown canonical fixture kind")
end

local function hex(bytes: string): string
	return (bytes:gsub(".", function(character)
		return string.format("%02x", character:byte())
	end))
end

--# Functions

function CanonicalTests.Run()
	local document = Rules.Entries(Serde.decode("json", Fs.readFile("libraries/bootstrap/ruleset.json")))
	local definition = Rules.Entries(document.canonical)

	for _, raw in Rules.Array(definition.cases) do
		local case = Rules.Entries(raw)
		local expected = Rules.Entries(case.expected)
		local value = materialize(case.input)
		local bytes = Canonical.Encode(value)

		if expected.missing then
			assert(bytes == nil, "missing root acquired canonical bytes")
			assert(not pcall(Canonical.Hash, value), "missing root acquired a fingerprint")
		else
			assert(bytes and hex(bytes) == expected.utf8_hex, "canonical byte mismatch: " .. tostring(case.name))
			assert(
				Serde.hash("sha256", bytes) == expected.sha256,
				"canonical fingerprint mismatch: " .. tostring(case.name)
			)
			assert(type(expected.text) == "string", "missing JSON byte fixture")
			assert(
				Canonical.Encode(Canonical.Decode(expected.text)) == bytes,
				"JSON decoder changed canonical bytes: " .. tostring(case.name)
			)
		end
	end

	for _, invalid in Rules.Array(definition.rejected_json) do
		assert(type(invalid) == "string", "invalid parser rejection fixture")
		assert(not pcall(Canonical.Decode, invalid), "malformed JSON accepted: " .. invalid)
	end
end

return CanonicalTests
