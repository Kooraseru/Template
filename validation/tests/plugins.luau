-- validation/tests/plugins.luau
--!strict

local Test = require("@testing")

--# Modules

local Plugins = require("../plugins")
local Cases = require("../../libraries/testing/cases")

--# Types

type Input = Cases.Patch & { Bundled: boolean }

--# Data

local contract: Plugins.Contract = {
	Capabilities = { "example.read", "example.write" },
	Permissions = { "filesystem.read" },
	Modes = { "builtin", "worker", "trusted" },
}

local baseline = {
	id = "example.reader",
	provides = { "example.read" },
	requires = {},
	permissions = {},
	entry = { mode = "builtin", name = "reader" },
}

--# Helpers

local function validate(input: Input): boolean
	return (pcall(Plugins.Validate, Cases.Apply(baseline, input), contract, input.Bundled))
end

--# Declaration

local definition: Test.Definition<Input, boolean> = {
	Name = "Independent plugin descriptors",
	Execute = validate,
	Cases = {
		{ Name = "Bundled registration", Input = { Bundled = true }, Expected = true },
		{ Name = "Forged builtin", Input = { Bundled = false }, Expected = false },
		{ Name = "Missing identifier", Input = { Bundled = true, remove = { "id" } }, Expected = false },
		{
			Name = "Version fields do not grant compatibility",
			Input = { Bundled = true, patch = { api_version = 1 } },
			Expected = false,
		},
		{
			Name = "Unknown capability",
			Input = { Bundled = true, patch = { provides = { "unknown" } } },
			Expected = false,
		},
		{
			Name = "Unknown permission",
			Input = { Bundled = true, patch = { permissions = { "unknown" } } },
			Expected = false,
		},
		{
			Name = "Unknown execution mode",
			Input = { Bundled = true, patch = { ["entry.mode"] = "unknown" } },
			Expected = false,
		},
		{ Name = "Missing entry name", Input = { Bundled = true, remove = { "entry.name" } }, Expected = false },
		{
			Name = "Builtin cannot supply executable path",
			Input = { Bundled = true, patch = { ["entry.path"] = "bin/provider" } },
			Expected = false,
		},
		{
			Name = "Independent worker descriptor",
			Input = {
				Bundled = false,
				patch = { entry = { mode = "worker", path = "bin/provider" }, permissions = { "filesystem.read" } },
			},
			Expected = true,
		},
		{
			Name = "Worker traversal rejected",
			Input = { Bundled = false, patch = { entry = { mode = "worker", path = "../provider" } } },
			Expected = false,
		},
	},
}

return Test.new(definition)
