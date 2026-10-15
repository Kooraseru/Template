--!strict
local fs = require("@lune/fs")
local serde = require("@lune/serde")
local cases = require("../../lib/cases")
local files = require("../../lib/files")
local rules = require("../../lib/rules")
local definitions = cases.read("ci/validation/ruleset.json", "rules.cases")
files.reset(definitions.root)
local path = definitions.root .. "/document.json"
for _, case in definitions.cases do
    fs.writeFile(path, serde.encode("json", case.document))
    cases.check(case.name, case.valid, function()
        rules.validate(case.input, rules.read(path))
        return true
    end)
end
files.reset(definitions.root)
print("Rule executor data cases passed")
