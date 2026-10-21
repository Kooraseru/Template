-- publication/repo/build.luau
--!strict

local Repository = {}

--# Modules

local Fs = require("@lune/fs")
local Process = require("@lune/process")
local Serde = require("@lune/serde")
local Config = require("../../libraries/registry/config")
local Files = require("../../libraries/bootstrap/files")

--# Types

export type Publication = {
	source: string,
	repository: string,
}

--# Constants

local OUTPUT_ROOT = "build/repo"
local TEMPLATE_ROOT = "publication/repo/templates"
local OPTIONAL_FILES = { "LICENSE", "CITATION.cff" }

--# Helpers

local function copyInputs(paths: { string })
	for _, path in ipairs(paths) do
		Config.Relative(path)

		assert(Fs.isDir(path) or Fs.isFile(path), "missing publication input: " .. path)

		Files.Copy(path, OUTPUT_ROOT .. "/" .. path, true)
	end
end

local function copyTemplates()
	for _, name in ipairs(Fs.readDir(TEMPLATE_ROOT)) do
		Files.Copy(TEMPLATE_ROOT .. "/" .. name, OUTPUT_ROOT .. "/" .. name)
	end
end

local function copyOptionalFiles()
	for _, name in ipairs(OPTIONAL_FILES) do
		if Fs.isFile(name) then
			Files.Copy(name, OUTPUT_ROOT .. "/" .. name)
		end
	end
end

--# Functions

-- The caller supplies validated configuration and the source-run identity.
-- All generated files belong to build/repo; templates override copied input names.
function Repository.Generate(config: Config.Config, publication: Publication): string
	assert(config.repository.enabled, "repository generation is disabled")

	Files.Reset(OUTPUT_ROOT)

	copyInputs(config.repository.include)
	copyTemplates()
	copyOptionalFiles()

	local metadata = Serde.encode("json", publication, true)

	Fs.writeFile(OUTPUT_ROOT .. "/publication.json", metadata)

	return OUTPUT_ROOT
end

function Repository.Run(): string
	local config = Config.Read()
	local publication = {
		source = Process.env.GITHUB_SHA or "local",
		repository = Process.env.GITHUB_REPOSITORY or "local",
	}

	return Repository.Generate(config, publication)
end

return Repository
