-- ci/libraries/bootstrap/outputs.luau
--!strict

local Outputs = {}

--# Modules

local Fs = require("@lune/fs")
local Rules = require("../registry/rules")
local definition = Rules.Read("ci/security/access/ruleset.json", "outputs.rules")

--# Functions

function Outputs.Encode(raw: unknown): string
	Rules.Validate(raw, definition)
	local values = raw :: { [string]: string }
	local keys: { string } = {}
	local keyPattern = assert(definition.key_pattern, "missing workflow output key pattern")

	for key in values do
		assert(key:match(keyPattern), "invalid workflow output name")
		table.insert(keys, key)
	end
	table.sort(keys)

	local lines = {}

	for _, key in keys do
		table.insert(lines, key .. "=" .. values[key])
	end

	return table.concat(lines, "\n") .. "\n"
end

function Outputs.Write(path: string?, values: { [string]: string })
	local text = Outputs.Encode(values)

	if path and path ~= "" then
		local existing = if Fs.isFile(path) then Fs.readFile(path) else ""
		Fs.writeFile(path, existing .. text)
	end
end

return Outputs
