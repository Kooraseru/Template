-- ci/validation/tests/rules.luau
--!strict

local RuleTests = {}

--# Modules

local Fs = require("@lune/fs")
local Serde = require("@lune/serde")
local Cases = require("../../lib/cases")
local Files = require("../../lib/files")
local Rules = require("../../lib/rules")

--# Helpers

local function runCase(case: Cases.Case, path: string)
    local document = Serde.encode("json", case.document)

    Fs.writeFile(path, document)

    Cases.Check(case.name, case.valid, function()
        local policy = Rules.Read(path)

        Rules.Validate(case.input, policy)

        return true
    end)
end

--# Functions

function RuleTests.Run()
    local definitions = Cases.Read("ci/validation/ruleset.json", "rules.cases")
    local root = definitions.root
    local path = root .. "/document.json"

    Files.Reset(root)

    local success, failure = pcall(function()
        for _, case in ipairs(definitions.cases) do
            runCase(case, path)
        end
    end)

    -- Requiring the module creates nothing; each run owns and removes its fixtures.
    Files.Reset(root)

    assert(success, tostring(failure))
end

return RuleTests
