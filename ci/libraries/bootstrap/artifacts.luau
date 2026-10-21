-- libraries/bootstrap/artifacts.luau
--!strict

local Artifacts = {}

--# Modules
local Fs = require("@lune/fs")
local Serde = require("@lune/serde")
local Config = require("../registry/config")
local Rules = require("../registry/rules")
local definition = Rules.Read("fabricator/distribution/ruleset.json", "manifest.rules")
--# Functions

--# Functions

function Artifacts.Verify(root: string)
	local manifestFile = assert(definition.manifest_file, "missing manifest filename")
	local hashAlgorithm = assert(definition.hash_algorithm, "missing manifest hash algorithm")
	local hashField = assert(definition.hash_field, "missing manifest hash field")
	local raw: unknown = Serde.decode("json", Fs.readFile(root .. "/" .. manifestFile))
	Rules.Validate(raw, definition)
	local manifest = Rules.Array(raw)
	local seen = {}

	for _, rawEntry in manifest do
		local entry = Rules.Entries(rawEntry)
		local path = Config.Relative(entry.path)
		seen[path] = true
		assert(Fs.isFile(root .. "/" .. path), "missing artifact: " .. path)
		assert(
			Serde.hash(hashAlgorithm, Fs.readFile(root .. "/" .. path)) == entry[hashField],
			"artifact checksum mismatch: " .. path
		)
	end

	local function inspect(directory: string, prefix: string)
		for _, name in Fs.readDir(directory) do
			local path = prefix .. name

			if Fs.isDir(directory .. "/" .. name) then
				inspect(directory .. "/" .. name, path .. "/")
			else
				assert(path == manifestFile or seen[path], "unlisted artifact: " .. path)
			end
		end
	end
	inspect(root, "")
end

return Artifacts
