-- ci/validation/tests/providers.luau
--!strict

local Test = require("../../libraries/testing/test")

--# Modules

local Plugins = require("../plugins")

--# Types

type Input = { Descriptors: { Plugins.Descriptor }, Selections: { [string]: string }? }

--# Helpers

local function provider(id: string, provides: { string }, requires: { string }): Plugins.Descriptor
	return {
		id = id,
		provides = provides,
		requires = requires,
		permissions = {},
		entry = { mode = "builtin", name = id },
	}
end

local function validate(input: Input): boolean
	local sources: { Plugins.Source } = {}

	for _, descriptor in input.Descriptors do
		table.insert(sources, { Descriptor = descriptor, Bundled = true })
	end

	return (
		pcall(Plugins.ValidateAll, sources, {
			Capabilities = { "example.read", "example.write" },
			Permissions = {},
			Modes = { "builtin" },
		}, input.Selections)
	)
end

--# Declaration

local definition: Test.Definition<Input, boolean> = {
	Name = "Provider discovery and dependency resolution",
	Execute = validate,
	Cases = {
		{
			Name = "Registered builtin",
			Input = { Descriptors = { provider("reader", { "example.read" }, {}) } },
			Expected = true,
		},
		{
			Name = "Missing required provider",
			Input = { Descriptors = { provider("writer", { "example.write" }, { "example.read" }) } },
			Expected = false,
		},
		{
			Name = "Duplicate identifier",
			Input = {
				Descriptors = { provider("same", { "example.read" }, {}), provider("same", { "example.write" }, {}) },
			},
			Expected = false,
		},
		{
			Name = "Ambiguous provider",
			Input = {
				Descriptors = { provider("first", { "example.read" }, {}), provider("second", { "example.read" }, {}) },
			},
			Expected = false,
		},
		{
			Name = "Selected provider",
			Input = {
				Descriptors = { provider("first", { "example.read" }, {}), provider("second", { "example.read" }, {}) },
				Selections = { ["example.read"] = "second" },
			},
			Expected = true,
		},
		{
			Name = "Unrelated selection rejected",
			Input = {
				Descriptors = { provider("reader", { "example.read" }, {}) },
				Selections = { ["example.read"] = "missing" },
			},
			Expected = false,
		},
		{
			Name = "Circular dependency",
			Input = {
				Descriptors = {
					provider("reader", { "example.read" }, { "example.write" }),
					provider("writer", { "example.write" }, { "example.read" }),
				},
			},
			Expected = false,
		},
		{
			Name = "Resolved dependency",
			Input = {
				Descriptors = {
					provider("reader", { "example.read" }, {}),
					provider("writer", { "example.write" }, { "example.read" }),
				},
			},
			Expected = true,
		},
	},
}

return Test.new(definition)
