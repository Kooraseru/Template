-- ci/validation/tests/artifacts.luau
--!strict
local Fs = require("@lune/fs")
local Serde = require("@lune/serde")
local VerifyArtifacts = require("../../lib/artifacts")
local Files = require("../../lib/files")
local Cases = require("../../lib/cases")
local definitions = Cases.Read("ci/validation/ruleset.json", "artifacts.cases")
local root = definitions.root

for _, case in definitions.cases do
    Files.Reset(root)
    local contents = table.clone(definitions.baseline.files)
    for name, value in case.files do
        contents[name] = value
    end
    for name, value in contents do
        Fs.writeFile(root .. "/" .. name, value)
    end
    local manifest = {}
    for _, entry in case.manifest or definitions.baseline.manifest do
        table.insert(
            manifest,
            { path = entry.path, sha256 = Serde.hash("sha256", entry.hash_contents) }
        )
    end
    Fs.writeFile(root .. "/manifest.json", Serde.encode("json", manifest))
    Cases.Check(case.name, case.valid, function()
        VerifyArtifacts(root)
        return true
    end)
end
Files.Reset(root)
print("Artifact data cases passed")
