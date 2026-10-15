-- ci/validation/workflows.luau
--!strict

local Workflows = {}

--# Modules

local Fs = require("@lune/fs")
local Serde = require("@lune/serde")
local Rules = require("../lib/rules")

--# Types

type ControlCheck = {
    source: string,
    path: string,
    default_type: string,
}

--# Helpers

local function readYaml(path: string): unknown
    local source = Fs.readFile(path)

    return Serde.decode("yaml", source)
end

local function validateControls(workflow: unknown, check: ControlCheck)
    local source = Fs.readFile(check.source)
    local controls = Rules.Entries(Serde.decode("json", source))
    local inputs = Rules.Entries(Rules.Property(workflow, check.path))
    local expectedCount = 0

    for key, rawDefinition in pairs(controls) do
        assert(type(key) == "string", "expected control name")

        local definition = Rules.Entries(rawDefinition)
        local rawInput = inputs[key]
        assert(rawInput ~= nil, "missing CI control: " .. key)

        local input = Rules.Entries(rawInput)
        local expectedType = definition.type or check.default_type

        assert(input.type == expectedType, "incorrect CI control type: " .. key)
        assert(input.default == definition.default, "incorrect CI control default: " .. key)

        if definition.options ~= nil then
            local choices = Rules.Array(definition.options)
            local offeredChoices = Rules.Array(input.options)

            for _, choice in ipairs(choices) do
                assert(type(choice) == "string", "expected control choice")
                assert(table.find(offeredChoices, choice), "missing CI choice: " .. key .. " / " .. choice)
            end
        end

        expectedCount += 1
    end

    local actualCount = 0

    for _ in pairs(inputs) do
        actualCount += 1
    end

    assert(actualCount == expectedCount, "workflow inputs differ from the control catalogue")
end

--# Functions

function Workflows.Run()
    local definitions = Rules.Read("ci/validation/ruleset.json", "workflows.rules")
    local workflow = readYaml(".github/workflows/ci.yml")
    local controlCheck = definitions.controls
    local actionRules = definitions.actions

    assert(controlCheck ~= nil, "missing control validation definition")
    assert(actionRules ~= nil, "missing action validation rules")

    Rules.Validate(workflow, definitions)
    validateControls(workflow, controlCheck)

    for _, name in ipairs(Fs.readDir(".github/actions")) do
        local path = ".github/actions/" .. name .. "/action.yml"

        if Fs.isFile(path) then
            local action = readYaml(path)

            Rules.Validate(action, actionRules)
        end
    end
end

return Workflows
