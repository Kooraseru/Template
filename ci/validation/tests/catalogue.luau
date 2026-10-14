--!strict
local catalogue = require("../../lib/catalogue")
local config = require("../../lib/config").read()
local cases = require("../../lib/cases")
local baseline = catalogue.read(config)
for _, case in cases.read("ci/validation/tests/catalogue.cases.json").cases do
    cases.check(case.name, case.valid, function()
        catalogue.validate(cases.apply(baseline, case))
        return true
    end)
end
print("Catalogue data cases passed")
