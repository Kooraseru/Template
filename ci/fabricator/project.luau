-- ci/fabricator/project.luau
--!strict

local Project = {}

--# Modules

local Fs = require("@lune/fs")
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
		if Fs.isFile("source/build.toml") then
			source = Fs.readFile("source/build.toml")
		end
	else
		source = Inputs.Read("source/build.toml")
	end

	return Project.Combine(repository, if source then Serde.decode("toml", source) else {})
end

return Project
