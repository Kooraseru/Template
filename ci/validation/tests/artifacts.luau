-- validation/tests/artifacts.luau
--!strict

local ArtifactTests = {}

--# Modules

local Fs = require("@lune/fs")
local Serde = require("@lune/serde")
local Artifacts = require("../../libraries/bootstrap/artifacts")
local Files = require("../../libraries/bootstrap/files")
local Cases = require("../../libraries/testing/cases")

--# Helpers

local function writeFixture(root: string, definitions: Cases.Document, case: Cases.Case)
	local contents = table.clone(definitions.baseline.files)

	for name, value in pairs(case.files) do
		contents[name] = value
	end

	for name, value in pairs(contents) do
		Fs.writeFile(root .. "/" .. name, value)
	end

	local manifest = {}
	local entries = case.manifest or definitions.baseline.manifest

	for _, entry in ipairs(entries) do
		table.insert(manifest, {
			path = entry.path,
			sha256 = Serde.hash("sha256", entry.hash_contents),
		})
	end

	local encoded = Serde.encode("json", manifest)

	Fs.writeFile(root .. "/manifest.json", encoded)
end

--# Functions

function ArtifactTests.Run()
	local definitions = Cases.Read("validation/ruleset.json", "artifacts.cases")
	local root = definitions.root

	local success, failure = pcall(function()
		for _, case in ipairs(definitions.cases) do
			Files.Reset(root)
			writeFixture(root, definitions, case)

			Cases.Check(case.name, case.valid, function()
				Artifacts.Verify(root)

				return true
			end)
		end
	end)

	-- Unexpected assertions must not leave a later run with a previous fixture.
	Files.Reset(root)

	assert(success, tostring(failure))
end

return ArtifactTests
