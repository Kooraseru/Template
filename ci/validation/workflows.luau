--!strict
local fs = require("@lune/fs")
local serde = require("@lune/serde")
local rules = require("../lib/rules")
local definitions = rules.read("ci/validation/workflows.rules.json")
local workflow = serde.decode("yaml", fs.readFile(".github/workflows/ci.yml"))
rules.validate(workflow, definitions)

local controls = serde.decode("json", fs.readFile("ci/control/options.json"))
local count = 0
for key, definition in controls do
    count += 1
    local input = assert(workflow.on.workflow_dispatch.inputs[key], "missing CI control: " .. key)
    assert(input.type == "choice" and input.default == definition.default, "incorrect CI control: " .. key)
    for _, choice in definition.options do
        assert(table.find(input.options, choice), "missing CI choice: " .. key .. " / " .. choice)
    end
end
local actual = 0
for _ in workflow.on.workflow_dispatch.inputs do actual += 1 end
assert(count == 12 and actual == count, "the manual CI panel must contain exactly twelve controls")
assert(workflow.jobs.gate.name == nil, "keep the required gate check name stable")
for name, job in workflow.jobs do
    local luneReady = false
    for _, step in job.steps or {} do
        if step.uses == "./.github/actions/setup-lune" then luneReady = true end
        if step.uses == "./.github/actions/setup-node" then
            assert(luneReady, "setup-node requires setup-lune first in job: " .. name)
        end
    end
end

for _, name in fs.readDir(".github/actions") do
    local path = ".github/actions/" .. name .. "/action.yml"
    if fs.isFile(path) then
        rules.validate(serde.decode("yaml", fs.readFile(path)), definitions.actions)
    end
end
print("Workflow data checks passed")
