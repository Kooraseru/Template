--!strict
local process = require("@lune/process")
local cases = require("../../lib/cases")
local definitions = cases.read("ci/access/tests/publication.cases.json")

for _, script in definitions.scripts do
    for _, case in definitions.cases do
        local arguments = table.clone(case.arguments)
        table.insert(arguments, script)
        local result = process.exec("bash", arguments, { env = case.env })
        assert(
            result.ok == case.ok,
            script .. ": " .. case.name .. " returned an unexpected result"
        )
    end
end
print("Publication operation data cases passed")
