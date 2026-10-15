-- ci/validation/tests/catalogue.luau
--!strict

local CatalogueTests = {}

--# Modules

local Catalogue = require("../../lib/catalogue")
local Config = require("../../lib/config")
local Cases = require("../../lib/cases")

--# Functions

function CatalogueTests.Run()
    local config = Config.Read()
    local definitions = Cases.Read("ci/validation/ruleset.json", "catalogue.cases")
    local configured = Catalogue.Read(config)
    local baseline = Cases.Apply(configured, definitions.baseline)

    for _, case in ipairs(definitions.cases) do
        Cases.Check(case.name, case.valid, function()
            local candidate = Cases.Apply(baseline, case)

            Catalogue.Validate(candidate)

            return true
        end)
    end
end

return CatalogueTests
