-- libraries/testing/cases.luau
--!strict

local Cases = {}

--# Modules

local Fs = require("@lune/fs")
local Serde = require("@lune/serde")
local Rules = require("../registry/rules")

--# Types

export type Patch = { patch: { [string]: unknown }?, remove: { string }? }

type ManifestEntry = { path: string, hash_contents: string }

export type Case = Patch & {
	name: string,
	valid: boolean,
	input: unknown,
	expected: unknown,
	document: unknown,
	files: { [string]: string },
	manifest: { ManifestEntry }?,
	arguments: { string },
	env: { [string]: string },
	ok: boolean,
}

export type Document = {
	controls_preserve_baseline: boolean?,
	controls: {
		{
			name: string,
			inputs: { [string]: string },
			expected: Rules.Document,
			valid: boolean,
			catalogue_valid: boolean?,
		}
	},
	root: string,
	baseline: Patch & { files: { [string]: string }, manifest: { ManifestEntry } },
	cases: { Case },
	configuration: { Case },
	policy: { Case },
	paths: { { input: string, valid: boolean } },
	repositories: { Case },
	outputs: { Case },
	scripts: { string },
	files: { [string]: string },
	commands: { { argv: { string }, windows_argv: { string }?, code: number, stdout_contains: string? } },
}

--# Helpers

local function copy(value: unknown): unknown

	if type(value) ~= "table" then
		return value
	end

	local result: Rules.Dictionary = {}

	for key, child in Rules.Entries(value) do
		result[key] = copy(child)
	end

	return result
end

--# Functions

function Cases.Read(path: string, section: string?): Document
	local raw: unknown = Serde.decode("json", Fs.readFile(path))

	if section then
		for _, key in string.split(section, ".") do
			raw = assert(Rules.Entries(raw)[key], "missing case section: " .. section)
		end
	end

	local document = Rules.Entries(raw)
	-- Fixture schemas vary by executor. Quarantine their decoded shape here;
	-- expected failures remain data and are exercised by the selected executor.
	for _, group in { "cases", "configuration", "policy", "paths", "repositories", "outputs" } do
		if document[group] then
			for _, entry in Rules.Array(document[group]) do
				local case = Rules.Entries(entry)

				assert(case.name == nil or type(case.name) == "string", "invalid case name")
				assert(case.valid == nil or type(case.valid) == "boolean", "invalid case expectation")
			end
		end
	end

	return document :: Document
end

-- Deep-copies the baseline; patches and removals cannot mutate later test inputs.
function Cases.Apply(baseline: unknown, case: Patch): unknown
	local result = Rules.Entries(copy(baseline))

	for path, value in case.patch or {} do
		local parts = string.split(path, ".")
		local parent = result

		for index = 1, #parts - 1 do
			parent = Rules.Entries(parent[tonumber(parts[index]) or parts[index]])
		end
		parent[tonumber(parts[#parts]) or parts[#parts]] = copy(value)
	end

	for _, key in case.remove or {} do
		local parts = string.split(key, ".")
		local parent = result

		for index = 1, #parts - 1 do
			parent = Rules.Entries(parent[tonumber(parts[index]) or parts[index]])
		end
		parent[tonumber(parts[#parts]) or parts[#parts]] = nil
	end

	return result
end

-- A declared rejection must throw; an optional expected value checks successful returns.
function Cases.Check(name: string, valid: boolean, operation: () -> unknown, expected: unknown)
	local ok, result = pcall(operation)

	assert(ok == valid, name .. ": unexpected validation result")

	if ok and expected ~= nil then
		assert(result == expected, name .. ": unexpected return value")
	end
end

return Cases
