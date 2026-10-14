--!strict
local config = require("../../lib/config")
local cases = require("../../lib/cases")
local definitions = cases.read("ci/validation/tests/config.cases.json")
local baseline = config.read()

for _, case in definitions.configuration do
    cases.check(case.name, case.valid, function()
        return config.validate(cases.apply(baseline, case))
    end)
end
for _, case in definitions.paths do
    cases.check(case.input, case.valid, function()
        return config.relative(case.input)
    end, if case.valid then case.input else nil)
end
print("Configuration data cases passed")
