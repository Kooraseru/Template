-- ci/validation/tests/gate.luau
--!strict

local GateTests = {}

--# Modules

local Cases = require("../../lib/cases")
local Rules = require("../../lib/rules")

--# Functions

function GateTests.Run()
    local definitions = Cases.Read("ci/validation/ruleset.json", "gate.cases")
    local policy = Rules.Read("ci/validation/ruleset.json", "gate.rules")

    for _, case in ipairs(definitions.cases) do
        Cases.Check(case.name, case.valid, function()
            local candidate = Cases.Apply(definitions.baseline, case)

            Rules.Validate(candidate, policy)

            return true
        end)
    end
end

return GateTests
