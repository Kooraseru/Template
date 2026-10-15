-- ci/validation/tests/catalogue.luau
--!strict
local Catalogue = require("../../lib/catalogue")
local config = require("../../lib/config").Read()
local Cases = require("../../lib/cases")
local definitions = Cases.Read("ci/validation/ruleset.json", "catalogue.cases")
local baseline = Cases.Apply(Catalogue.Read(config), definitions.baseline)
for _, case in definitions.cases do
    Cases.Check(case.name, case.valid, function()
        Catalogue.Validate(Cases.Apply(baseline, case))
        return true
    end)
end
print("Catalogue data cases passed")
