-- validation/tests/workshop.luau
--!strict

local Test = require("@testing")

--# Modules

local Workshop = require("../workshop")
local Cases = require("../../libraries/testing/cases")

--# Types

type Input = Cases.Patch & {
	Files: { Workshop.File }?,
	Providers: { [string]: { string } }?,
	Selections: { [string]: string }?,
}

--# Data

local baseline = {
	id = "example.content",
	name = "Example content",
	assets = { { path = "assets/content.bin", requires = "example.read" } },
}

--# Helpers

local function validate(input: Input): boolean
	return (
		pcall(function()
			local descriptor = Workshop.Validate(Cases.Apply(baseline, input))

			if input.Files then
				Workshop.Inventory(descriptor, input.Files, { Files = 2, Bytes = 100, AssetBytes = 80 })
			end

			if input.Providers then
				Workshop.Resolve(descriptor, input.Providers, input.Selections)
			end
		end)
	)
end

--# Declaration

local definition: Test.Definition<Input, boolean> = {
	Name = "Independent data-only Workshop contract",
	Execute = validate,
	Cases = {
		{ Name = "Data descriptor", Input = {}, Expected = true },
		{ Name = "Empty assets rejected", Input = { patch = { assets = {} } }, Expected = false },
		{ Name = "Traversal rejected", Input = { patch = { ["assets.1.path"] = "../outside" } }, Expected = false },
		{ Name = "Missing capability", Input = { remove = { "assets.1.requires" } }, Expected = false },
		{
			Name = "Plugin entry cannot grant authority",
			Input = { patch = { entry = { mode = "builtin", name = "reader" } } },
			Expected = false,
		},
		{
			Name = "Permissions cannot grant authority",
			Input = { patch = { permissions = { "execute" } } },
			Expected = false,
		},
		{
			Name = "Valid inventory",
			Input = {
				Files = {
					{ Path = "workshop.toml", Bytes = 10, Executable = false },
					{ Path = "assets/content.bin", Bytes = 20, Executable = false },
				},
			},
			Expected = true,
		},
		{
			Name = "Missing asset",
			Input = { Files = { { Path = "workshop.toml", Bytes = 10, Executable = false } } },
			Expected = false,
		},
		{
			Name = "Undeclared file",
			Input = { Files = { { Path = "unlisted", Bytes = 10, Executable = false } } },
			Expected = false,
		},
		{
			Name = "Executable content rejected",
			Input = { Files = { { Path = "assets/content.bin", Bytes = 10, Executable = true } } },
			Expected = false,
		},
		{
			Name = "Oversized asset",
			Input = { Files = { { Path = "assets/content.bin", Bytes = 81, Executable = false } } },
			Expected = false,
		},
		{ Name = "Missing provider", Input = { Providers = {} }, Expected = false },
		{
			Name = "Ambiguous provider",
			Input = { Providers = { ["example.read"] = { "first", "second" } } },
			Expected = false,
		},
		{
			Name = "Explicit provider selection",
			Input = {
				Providers = { ["example.read"] = { "first", "second" } },
				Selections = { ["example.read"] = "second" },
			},
			Expected = true,
		},
	},
}

return Test.new(definition)
