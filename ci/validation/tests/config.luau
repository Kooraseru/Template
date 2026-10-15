-- ci/validation/tests/config.luau
--!strict
local Config = require("../../lib/config")
local Cases = require("../../lib/cases")
local definitions = Cases.Read("ci/validation/ruleset.json", "config.cases")
local baseline = Config.Read()

for _, case in definitions.configuration do
    Cases.Check(case.name, case.valid, function()
        return Config.Validate(Cases.Apply(baseline, case))
    end)
end
for _, case in definitions.paths do
    Cases.Check(case.input, case.valid, function()
        return Config.Relative(case.input)
    end, if case.valid then case.input else nil)
end
print("Configuration data cases passed")
