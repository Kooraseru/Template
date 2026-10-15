-- ci/access/tests/publication.luau
--!strict
local Process = require("@lune/process")
local Cases = require("../../lib/cases")
local definitions = Cases.Read("ci/access/tests/publication.cases.json")

for _, script in definitions.scripts do
    for _, case in definitions.cases do
        local arguments = table.clone(case.arguments)
        table.insert(arguments, script)
        local result = Process.exec("bash", arguments, { env = case.env })
        assert(
            result.ok == case.ok,
            script .. ": " .. case.name .. " returned an unexpected result"
        )
    end
end
print("Publication operation data cases passed")
