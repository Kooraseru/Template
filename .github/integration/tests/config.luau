-- .github/integration/tests/config.luau
--!strict

local ControlTests = {}

--# Modules

local Project = require("../../../fabricator/project")
local Serde = require("@lune/serde")
local Controls = require("../config")
local Config = require("../../../libraries/registry/config")
local Catalogue = require("../../../libraries/registry/catalogue")
local Cases = require("../../../libraries/testing/cases")
local Rules = require("../../../libraries/registry/rules")

--# Functions

function ControlTests.Run()
	local previousValue = Controls.Read
	local success, failure = pcall(function()
		local definitions = Cases.Read("validation/ruleset.json", "config.cases")
		local baseline = Project.Read()
		local originalBaseline = Serde.encode("json", baseline)

		for _, case in definitions.controls do
			Controls.Read = function()
				return case.inputs
			end
			Cases.Check(case.name, case.valid, function()
				local selected = Config.Validate(Controls.Apply(baseline))
				Rules.Validate({ config = selected, targets = Catalogue.Targets(selected) }, case.expected)

				if case.catalogue_valid ~= nil then
					Cases.Check(case.name, case.catalogue_valid, function()
						Catalogue.Validate(Catalogue.Read(selected))

						return true
					end)
				end

				return true
			end)

			if definitions.controls_preserve_baseline then
				assert(Serde.encode("json", baseline) == originalBaseline, "overrides mutated the baseline")
			end
		end
	end)

	Controls.Read = previousValue

	assert(success, tostring(failure))
end

return ControlTests
