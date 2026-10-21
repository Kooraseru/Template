-- fabricator/tests/project.luau
--!strict

local Test = require("@testing")

--# Modules

local Project = require("../project")
local Config = require("../../libraries/registry/config")
local Shape = require("../../libraries/registry/shape")

--# Types

type Input = { Repository: Shape.Object?, Source: Shape.Object }

--# Helpers

local function combine(input: Input): boolean

	local repository = input.Repository
		or {
			repository = { enabled = false, publish = false, include = { "src" } },
			pages = { enabled = false, publish = false },
			release = { enabled = false, publish = false },
		}
	local success = pcall(function()
		local resolved = Config.Validate(Project.Combine(repository, input.Source))
		assert(resolved.build.runner ~= "", "missing default build environment")
		assert(not resolved.release.publish, "source changed publication authority")
	end)

	return success
end

--# Declaration

local definition: Test.Definition<Input, boolean> = {
	Name = "Build configuration ownership",
	Execute = combine,
	Cases = {
		{ Name = "Source-free template uses build defaults", Input = { Source = {} }, Expected = true },
		{
			Name = "Source declares commands and package paths",
			Input = { Source = { build = { commands = { { "cargo", "build" } }, package_paths = { "build/bin" } } } },
			Expected = true,
		},
		{
			Name = "Source cannot enable release publication",
			Input = { Source = { release = { publish = true } } },
			Expected = false,
		},
		{ Name = "Source rejects false build settings", Input = { Source = { build = false } }, Expected = false },
		{ Name = "Source cannot declare signing controls", Input = { Source = { signing = {} } }, Expected = false },
		{
			Name = "Source rejects unknown build configuration",
			Input = { Source = { dependencies = {} } },
			Expected = false,
		},
		{
			Name = "Repository cannot own application commands",
			Input = { Repository = { build = {} }, Source = {} },
			Expected = false,
		},
	},
}

return Test.new(definition)
