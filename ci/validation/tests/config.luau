-- ci/validation/tests/config.luau
--!strict

local ConfigTests = {}

--# Modules

local Config = require("../../lib/config")
local Cases = require("../../lib/cases")

--# Functions

function ConfigTests.Run()
    local definitions = Cases.Read("ci/validation/ruleset.json", "config.cases")
    local baseline = Config.Read()

    for _, case in ipairs(definitions.configuration) do
        Cases.Check(case.name, case.valid, function()
            local candidate = Cases.Apply(baseline, case)

            return Config.Validate(candidate)
        end)
    end

    for _, case in ipairs(definitions.paths) do
        local expected = if case.valid then case.input else nil

        Cases.Check(case.input, case.valid, function()
            return Config.Relative(case.input)
        end, expected)
    end
end

return ConfigTests
