-- ci/fabricator/tests/targets.luau
--!strict

local Test = require("../../libraries/testing/test")

--# Modules

local Targets = require("../targets")
local Fs = require("@lune/fs")

--# Types

type Input = { Targets: unknown, Select: { string }? }

--# Helpers

local function cargoConfig(): boolean
	local path = "build/tests/cargo-configuration"
	Fs.writeDir(path)
	local filename = path .. "/config.toml"
	if Fs.isFile(filename) then Fs.removeFile(filename) end
	local target: Targets.Target = { id = "application", system = "cargo", path = path }
	local plain = Targets.Commands(target)[1]
	assert(plain[1] == "cargo" and plain[2] == "build", "Cargo must not require a configuration file")
	Fs.writeFile(filename, "[build]\\n")
	local configured = Targets.Commands(target)[1]
	Fs.removeFile(filename)
	assert(configured[1] == "cargo" and configured[2] == "--config" and configured[3] == filename, "Cargo configuration not forwarded explicitly")
	assert(table.find(configured, "build") and table.find(configured, path .. "/Cargo.toml"), "Cargo manifest path changed")
	return true
end

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

local suite = Test.new(definition)
local original = suite.Run
function suite:Run(onReport)
	cargoConfig()
	return original(self, onReport)
end
return suite
