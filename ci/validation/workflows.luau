-- ci/validation/workflows.luau
--!strict
local Fs = require("@lune/fs")
local Serde = require("@lune/serde")
local Rules = require("../lib/rules")
local definitions = Rules.Read("ci/validation/ruleset.json", "workflows.rules")
local workflow = Serde.decode("yaml", Fs.readFile(".github/workflows/ci.yml"))
Rules.Validate(workflow, definitions)

local controlCheck = assert(definitions.controls, "missing control validation definition")
local controls = Rules.Entries(Serde.decode("json", Fs.readFile(controlCheck.source)))
local inputs = Rules.Property(workflow, controlCheck.path)
assert(type(inputs) == "table", "missing workflow inputs")
local count = 0
for key, rawDefinition in controls do
    assert(type(key) == "string", "expected control name")
    local definition = Rules.Entries(rawDefinition)
    count += 1
    local input = Rules.Entries(assert(Rules.Entries(inputs)[key], "missing CI control: " .. key))
    assert(type(input) == "table", "invalid CI control: " .. key)
    assert(input.type == (definition.type or controlCheck.default_type), "incorrect CI control type: " .. key)
    assert(input.default == definition.default, "incorrect CI control default: " .. key)
    for _, choice in Rules.Entries(definition.options or {}) do
        assert(type(choice) == "string", "expected control choice")
        assert(type(input.options) == "table" and table.find(Rules.Array(input.options), choice), "missing CI choice: " .. key .. " / " .. choice)
    end
end
local actual = 0
for _ in inputs do actual += 1 end
assert(actual == count, "workflow inputs differ from the control catalogue")

for _, name in Fs.readDir(".github/actions") do
    local path = ".github/actions/" .. name .. "/action.yml"
    if Fs.isFile(path) then
        Rules.Validate(Serde.decode("yaml", Fs.readFile(path)), assert(definitions.actions, "missing action rules"))
    end
end
print("Workflow data checks passed")
