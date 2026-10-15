--!strict
local cases = require("../../lib/cases")
local rules = require("../../lib/rules")
local definitions = cases.read("ci/validation/ruleset.json", "gate.cases")
local policy = rules.read("ci/validation/ruleset.json", "gate.rules")
for _, case in definitions.cases do
    cases.check(case.name, case.valid, function()
        rules.validate(cases.apply(definitions.baseline, case), policy)
        return true
    end)
end
print("Gate data cases passed")
