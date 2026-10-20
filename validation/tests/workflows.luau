-- validation/tests/workflows.luau
--!strict

local Test = require("@testing")

--# Modules

local Fs = require("@lune/fs")
local Serde = require("@lune/serde")
local Cases = require("../../libraries/testing/cases")
local Workflows = require("../workflows")

--# Helpers

local function validate(input: Cases.Patch): boolean
	local workflow = Serde.decode("yaml", Fs.readFile(".github/workflows/ci.yml"))
	return (pcall(Workflows.CheckBoundaries, Cases.Apply(workflow, input)))
end

--# Declaration

local definition: Test.Definition<Cases.Patch, boolean> = {
	Name = "Workflow stage boundaries",
	Execute = validate,
	Cases = {
		{ Name = "Template stage boundaries", Input = {}, Expected = true },
		{ Name = "Missing build stage", Input = { remove = { "jobs.build" } }, Expected = false },
		{
			Name = "Build cannot request publication writes",
			Input = { patch = { ["jobs.build.permissions"] = { contents = "write" } } },
			Expected = false,
		},
		{
			Name = "Release publication requires gate dependency",
			Input = { patch = { ["jobs.publish-release.needs"] = { "validate" } } },
			Expected = false,
		},
		{
			Name = "Unconditional publication rejected",
			Input = { patch = { ["jobs.publish-repository.if"] = "always()" } },
			Expected = false,
		},
	},
}

return Test.new(definition)
