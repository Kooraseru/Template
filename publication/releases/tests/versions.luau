-- publication/releases/tests/versions.luau
--!strict

local Test = require("@testing")

--# Modules

local D = require("../../../libraries/bootstrap/documents")
local C = require("../../../libraries/bootstrap/canonical")
local Versions = require("../versions")
local Fixture = require("./fixture")

--# Types

type Input = { Version: string?, Scenario: C.Value? }

--# Helpers

local fixture: Fixture.Repository? = nil

local function validate(input: Input): boolean
	if input.Version then
		return (pcall(Versions.Parse, input.Version))
	end
	local repository = fixture or Fixture.Create()
	fixture = repository
	local scenario = assert(input.Scenario)
	local expanded = Fixture.Expand(D.Required(scenario, "input"), repository)
	return (pcall(Versions.Validate, D.Plain(expanded), repository.Commits.merge, repository.Root))
end

local function cases(): { Test.Case<Input, boolean> }
	local result: { Test.Case<Input, boolean> } = {}
	for _, version in { "0.1.0", "1.2.0", "12.34.56", "1.3.0-pre.0", "1.3.0-pre.1", "1.3.0-pre.10" } do
		table.insert(result, { Name = version, Input = { Version = version }, Expected = true })
	end
	for _, version in
		{
			"1.2",
			"v1.2.0",
			"01.2.0",
			"1.02.0",
			"1.2.00",
			"1.2.0-pre.01",
			"1.2.0-beta.1",
			"1.2.0-rc.1",
			"1.2.0-pre",
			"1.2.0+build.1",
			"Release",
			"../1.2.0",
		}
	do
		table.insert(result, { Name = version, Input = { Version = version }, Expected = false })
	end
	for _, scenario in D.Items(D.Required(D.Read("publication/releases/ruleset.json"), "cases"), "releases") do
		table.insert(result, {
			Name = D.Text(scenario, "name"),
			Input = { Scenario = scenario },
			Expected = D.Get(scenario, "valid") == true,
		})
	end
	return result
end

--# Declaration

local definition: Test.Definition<Input, boolean> =
	{ Name = "SemVer publication selections", Execute = validate, Cases = cases() }

return Test.new(definition)
