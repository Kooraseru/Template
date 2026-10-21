-- ci/validation/tests/workflows.luau
--!strict

local Test = require("../../libraries/testing/test")

--# Modules

local Fs = require("@lune/fs")
local Serde = require("@lune/serde")
local Cases = require("../../libraries/testing/cases")
local Workflows = require("../workflows")
local Rules = require("../../libraries/registry/rules")

--# Helpers

local function validate(input: Cases.Patch): boolean
	local workflow = Serde.decode("yaml", Fs.readFile(".github/workflows/ci.yml"))
	local candidate = Cases.Apply(workflow, input)
	local definitions = Rules.Read("ci/validation/ruleset.json", "workflows.rules")
	local actionRules = assert(definitions.actions, "missing action validation rules")

	return (
		pcall(function()
			Workflows.CheckBoundaries(candidate)
			Workflows.CheckActions(candidate, actionRules)
		end)
	)
end

--# Declaration

local definition: Test.Definition<Cases.Patch, boolean> = {
	Name = "Workflow stage boundaries",
	Execute = validate,
	Cases = {
		{ Name = "Template stage boundaries", Input = {}, Expected = true },
		{
			Name = "Missing colocated action rejected",
			Input = { patch = { ["jobs.pages.steps"] = { { uses = "./publication/pages/missing" } } } },
			Expected = false,
		},
		{
			Name = "Local action cannot escape the repository",
			Input = { patch = { ["jobs.pages.steps"] = { { uses = "./../outside" } } } },
			Expected = false,
		},
		{
			Name = "Gate still evaluates failed prerequisites",
			Input = { patch = { ["jobs.gate.if"] = "success()" } },
			Expected = false,
		},
		{
			Name = "Gate cannot omit optional image results",
			Input = {
				patch = {
					["jobs.gate.needs"] = {
						"validate",
						"build",
						"repository",
						"pages",
						"release",
						"validation-receipt",
					},
				},
			},
			Expected = false,
		},
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
