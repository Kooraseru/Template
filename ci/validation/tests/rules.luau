-- ci/validation/tests/rules.luau
--!strict
local Fs = require("@lune/fs")
local Serde = require("@lune/serde")
local Cases = require("../../lib/cases")
local Files = require("../../lib/files")
local Rules = require("../../lib/rules")
local definitions = Cases.Read("ci/validation/ruleset.json", "rules.cases")
Files.Reset(definitions.root)
local path = definitions.root .. "/document.json"
for _, case in definitions.cases do
    Fs.writeFile(path, Serde.encode("json", case.document))
    Cases.Check(case.name, case.valid, function()
        Rules.Validate(case.input, Rules.Read(path))
        return true
    end)
end
Files.Reset(definitions.root)
print("Rule executor data cases passed")
