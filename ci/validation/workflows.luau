--!strict
local fs = require("@lune/fs")
local serde = require("@lune/serde")
local rules = require("../lib/rules")
local definitions = rules.read("ci/validation/workflows.rules.json")
local workflow = serde.decode("yaml", fs.readFile(".github/workflows/ci.yml"))
rules.validate(workflow, definitions)

for _, name in fs.readDir(".github/actions") do
    local path = ".github/actions/" .. name .. "/action.yml"
    if fs.isFile(path) then
        rules.validate(serde.decode("yaml", fs.readFile(path)), definitions.actions)
    end
end
print("Workflow data checks passed")
