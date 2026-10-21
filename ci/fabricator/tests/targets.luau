-- ci/fabricator/tests/targets.luau
--!strict

local Test = require("../../libraries/testing/test")

--# Modules

local Targets = require("../targets")

--# Types

type Input = { Targets: unknown, Select: { string }? }

--# Helpers

local function validate(input: Input): boolean
	return (
		pcall(function()
			local targets = Targets.Validate(input.Targets)
			Targets.Select(targets, input.Select)
		end)
	)
end

--# Declaration

local definition: Test.Definition<Input, boolean> = {
	Name = "Explicit project targets",
	Execute = validate,
	Cases = {
		{ Name = "No mandatory application language", Input = { Targets = {} }, Expected = true },
		{
			Name = "Cargo source",
			Input = { Targets = { { id = "app", system = "cargo", path = "src/custom" } } },
			Expected = true,
		},
		{
			Name = "Non-Rust source",
			Input = { Targets = { { id = "native", system = "cmake", path = "src/cpp" } } },
			Expected = true,
		},
		{
			Name = "Unknown build system",
			Input = { Targets = { { id = "app", system = "magic", path = "src" } } },
			Expected = false,
		},
		{
			Name = "Traversal",
			Input = { Targets = { { id = "app", system = "cargo", path = "../outside" } } },
			Expected = false,
		},
		{
			Name = "Unsafe output identifier",
			Input = { Targets = { { id = "../app", system = "cmake", path = "src" } } },
			Expected = false,
		},
		{
			Name = "Unknown fields",
			Input = { Targets = { { id = "app", system = "cargo", path = "src", version = 1 } } },
			Expected = false,
		},
		{ Name = "Unknown selection", Input = { Targets = {}, Select = { "missing" } }, Expected = false },
		{
			Name = "Select CMake independently",
			Input = {
				Targets = {
					{ id = "rust", system = "cargo", path = "src/rust" },
					{ id = "native", system = "cmake", path = "src/native" },
				},
				Select = { "native" },
			},
			Expected = true,
		},
	},
}

return Test.new(definition)
