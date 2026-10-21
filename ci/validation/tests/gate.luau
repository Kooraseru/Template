-- ci/validation/tests/gate.luau
--!strict

local Test = require("../../libraries/testing/test")

--# Modules

local Cases = require("../../libraries/testing/cases")
local Rules = require("../../libraries/registry/rules")

--# Data

local baseline = {
	["results"] = {
		["validate"] = {
			["result"] = "success",
		},
		["build"] = {
			["result"] = "success",
		},
		["repository"] = {
			["result"] = "skipped",
		},
		["pages"] = {
			["result"] = "skipped",
		},
		["release"] = {
			["result"] = "skipped",
		},
		["images"] = {
			["result"] = "skipped",
		},
	},
	["enabled"] = {
		["repository"] = "false",
		["pages"] = "false",
		["release"] = "false",
		["images"] = "false",
	},
}

--# Helpers

local function validate(input: Cases.Patch): boolean
	return (
		pcall(function()
			Rules.Validate(Cases.Apply(baseline, input), Rules.Read("ci/validation/ruleset.json", "gate.rules"))
		end)
	)
end

--# Declaration

local definition: Test.Definition<Cases.Patch, boolean> = {
	Name = "Gate",
	Execute = validate,
	Cases = {
		{
			["Name"] = "disabled outputs",
			["Input"] = {
				["patch"] = {},
			},
			["Expected"] = true,
		},
		{
			["Name"] = "build failure",
			["Input"] = {
				["patch"] = {
					["results.build.result"] = "failure",
				},
			},
			["Expected"] = false,
		},
		{
			["Name"] = "validation failure",
			["Input"] = {
				["patch"] = {
					["results.validate.result"] = "failure",
				},
			},
			["Expected"] = false,
		},
		{
			["Name"] = "enabled Pages skipped",
			["Input"] = {
				["patch"] = {
					["enabled.pages"] = "true",
				},
			},
			["Expected"] = false,
		},
		{
			["Name"] = "enabled Pages success",
			["Input"] = {
				["patch"] = {
					["enabled.pages"] = "true",
					["results.pages.result"] = "success",
				},
			},
			["Expected"] = true,
		},
		{
			["Name"] = "missing eligibility",
			["Input"] = {
				["remove"] = {
					"enabled",
				},
				["patch"] = {},
			},
			["Expected"] = false,
		},
	},
}

return Test.new(definition)
