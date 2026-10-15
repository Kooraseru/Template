-- ci/control/tests/config.luau
--!strict
local Fs = require("@lune/fs")
local Serde = require("@lune/serde")
local Controls = require("../config")
local Config = require("../../lib/config")
local Catalogue = require("../../lib/catalogue")
local Cases = require("../../lib/cases")
local Rules = require("../../lib/rules")

local definitions = Cases.Read("ci/validation/ruleset.json", "config.cases")
local baseline = Serde.decode("toml", Fs.readFile("ci/config.toml"))
local originalRead = Controls.Read
local originalBaseline = Serde.encode("json", baseline)
for _, case in definitions.controls do
    Controls.Read = function() return case.inputs end
    Cases.Check(case.name, case.valid, function()
        local selected = Config.Validate(Controls.Apply(baseline))
        Rules.Validate({ config = selected, targets = Catalogue.Targets(selected) }, case.expected)
        if case.catalogue_valid ~= nil then
            Cases.Check(case.name, case.catalogue_valid, function()
                Catalogue.Validate(Catalogue.Read(selected))
                return true
            end)
        end
        return true
    end)
    if definitions.controls_preserve_baseline then
        assert(Serde.encode("json", baseline) == originalBaseline, "overrides mutated the baseline")
    end
end
Controls.Read = originalRead
print("CI control configuration cases passed")
