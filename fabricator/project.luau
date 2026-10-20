-- fabricator/project.luau
--!strict

local Project = {}

--# Modules

local Fs = require("@lune/fs")
local Process = require("@lune/process")
local Serde = require("@lune/serde")
local Inputs = require("../libraries/bootstrap/inputs")
local Shape = require("../libraries/registry/shape")

--# Functions

function Project.Combine(repository: unknown, source: unknown): Shape.Object

	local result = Shape.Object(repository, { "repository", "pages", "release" })
	local application = Shape.Object(source, { "build", "images", "targets" })

	result.build = if application.build == nil then {} else application.build
	result.images = if application.images == nil then { enabled = false, names = {} } else application.images
	result.targets = if application.targets == nil then {} else application.targets

	return result
end

function Project.Read(): Shape.Object

	local repository: unknown = Serde.decode("toml", Inputs.Read("config/project.toml"))
	local source: string?

	if Inputs.ref == "" then
		if Fs.isFile("src/build.toml") then
			source = Fs.readFile("src/build.toml")
		end
	else
		local exists = Process.exec("git", { "cat-file", "-e", Inputs.ref .. ":src/build.toml" })

		if not exists.ok then
			-- Historical snapshots predate the source-owned build declaration.
			return repository :: Shape.Object
		end

		source = Inputs.Read("src/build.toml")
	end

	return Project.Combine(repository, if source then Serde.decode("toml", source) else {})
end

return Project
