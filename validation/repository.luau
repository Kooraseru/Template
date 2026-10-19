-- validation/repository.luau
--!strict

local Repository = {}

--# Modules

local Fs = require("@lune/fs")
local Rules = require("../libraries/registry/rules")
local Config = require("../libraries/registry/config")
local Catalogue = require("../libraries/registry/catalogue")
local Targets = require("../fabricator/targets")

--# Types

type Check = Rules.RepositoryCheck

--# Helpers

local function validateDirectoryEntries(check: Check)
	local path = check.path
	local expectedEntries = check.expected

	assert(path ~= nil, "missing check path")
	assert(expectedEntries ~= nil, "missing expected entries")

	local entries = Fs.readDir(path)
	local expected = table.clone(expectedEntries)

	table.sort(entries)
	table.sort(expected)

	assert(table.concat(entries, "\n") == table.concat(expected, "\n"), "unexpected directory entries")
end

local function validateAbsentFiles(check: Check)
	local paths = check.paths
	assert(paths ~= nil, "missing check paths")

	for _, path in ipairs(paths) do
		assert(not Fs.isFile(path), "unexpected file: " .. path)
	end
end

local function validateConfiguredPaths(check: Check, config: Config.Config)
	local configPath = check.config_path
	assert(configPath ~= nil, "missing config path")

	local paths = Rules.Array(Rules.Property(config, configPath))

	for _, path in ipairs(paths) do
		assert(type(path) == "string", "expected configured path")
		assert(Fs.isFile(path) or Fs.isDir(path), "missing configured input: " .. path)
	end
end

local function validateFileContents(check: Check)
	local path = check.path
	local text = check.text

	assert(path ~= nil, "missing check path")
	assert(text ~= nil, "missing check text")

	local contents = Fs.readFile(path)

	assert(contents:find(text, 1, true), "missing required file content")
end

--# Functions

function Repository.Run()
	local config = Config.Read()
	local definitions = Rules.Read("validation/ruleset.json", "repository")
	local checks = definitions.checks

	assert(checks ~= nil, "missing repository checks")

	Catalogue.Validate(Catalogue.Read(config))
	Targets.Discover(config.targets)

	local operations = {
		directory_entries = validateDirectoryEntries,
		absent_files = validateAbsentFiles,
		existing_config_paths = function(check: Check)
			validateConfiguredPaths(check, config)
		end,
		file_contains = validateFileContents,
	}

	-- The literal registry above owns its keys; JSON selects through this typed view.
	local available: { [string]: (Check) -> () } = operations

	for _, check in ipairs(checks) do
		local execute = available[check.operation]

		assert(execute ~= nil, "unknown filesystem check: " .. check.operation)

		execute(check)
	end

end

return Repository
