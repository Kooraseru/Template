-- ci/validation/tests/gate.luau
--!strict
local Cases = require("../../lib/cases")
local Rules = require("../../lib/rules")
local definitions = Cases.Read("ci/validation/ruleset.json", "gate.cases")
local policy = Rules.Read("ci/validation/ruleset.json", "gate.rules")
for _, case in definitions.cases do
    Cases.Check(case.name, case.valid, function()
        Rules.Validate(Cases.Apply(definitions.baseline, case), policy)
        return true
    end)
end
print("Gate data cases passed")
