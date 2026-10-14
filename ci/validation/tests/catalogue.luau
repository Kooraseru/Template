--!strict
local catalogue = require("../../lib/catalogue")
local config = require("../../lib/config").read()
local cases = require("../../lib/cases")
local definitions = cases.read("ci/validation/tests/catalogue.cases.json")
local baseline = cases.apply(catalogue.read(config), definitions.baseline)
for _, case in definitions.cases do
    cases.check(case.name, case.valid, function()
        catalogue.validate(cases.apply(baseline, case))
        return true
    end)
end
print("Catalogue data cases passed")
