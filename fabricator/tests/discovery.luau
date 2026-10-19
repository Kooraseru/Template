-- fabricator/tests/discovery.luau
--!strict

local Test = require("@testing")

--# Modules

local Fs = require("@lune/fs")
local Inputs = require("../../libraries/bootstrap/inputs")
local Files = require("../../libraries/bootstrap/files")
local Targets = require("../targets")

--# Types

type Input = { System: string, Manifest: string?, ExpectedCommand: string }

--# Helpers

local function discover(input: Input): boolean
	local root = "build/tests/target-discovery"
	local previous = Inputs.ref
	Inputs.ref = ""
	Files.Reset(root)
	local success, result = pcall(function()
		if input.Manifest then
			Fs.writeFile(root .. "/" .. input.Manifest, "# Synthetic discovery input\n")
		end

		local targets = Targets.Discover({ { id = "fixture", system = input.System, path = root } })
		local commands = Targets.Commands(targets[1])

		return #targets == 1 and commands[1][1] == input.ExpectedCommand
	end)

	Inputs.ref = previous
	Files.Reset(root)

	return success and result == true
end

--# Declaration

local definition: Test.Definition<Input, boolean> = {
	Name = "Source target discovery",
	Execute = discover,
	Cases = {
		{
			Name = "Cargo manifest outside conventional folders",
			Input = { System = "cargo", Manifest = "Cargo.toml", ExpectedCommand = "cargo" },
			Expected = true,
		},
		{
			Name = "CMake manifest without Rust",
			Input = { System = "cmake", Manifest = "CMakeLists.txt", ExpectedCommand = "cmake" },
			Expected = true,
		},
		{ Name = "Missing native manifest", Input = { System = "cmake", ExpectedCommand = "cmake" }, Expected = false },
		{
			Name = "Cargo cannot consume a CMake target",
			Input = { System = "cargo", Manifest = "CMakeLists.txt", ExpectedCommand = "cargo" },
			Expected = false,
		},
	},
}

return Test.new(definition)
