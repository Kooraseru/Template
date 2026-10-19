-- security/access/tests/policy.luau
--!strict

local PolicyTests = {}

--# Modules

local Policy = require("../policy")
local Context = require("../context")
local Outputs = require("../../../libraries/bootstrap/outputs")
local Cases = require("../../../libraries/testing/cases")

--# Functions

function PolicyTests.Run()
	local definitions = Cases.Read("security/access/ruleset.json", "policy.cases")

	for _, case in definitions.policy do
		local result = Policy.CanPublish(Cases.Apply(definitions.baseline, case))

		assert(result == case.valid, case.name .. ": unexpected publication eligibility")
	end

	for index, case in definitions.repositories do
		assert(Context.Repository(case.input) == case.expected, "repository case " .. tostring(index))
	end

	for index, case in definitions.outputs do
		Cases.Check("output case " .. tostring(index), case.valid, function()
			return Outputs.Encode(case.input)
		end, case.expected)
	end
end

return PolicyTests
