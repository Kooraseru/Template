--!strict
local fs = require("@lune/fs")
local serde = require("@lune/serde")
local artifacts = require("../../lib/artifacts")
local files = require("../../lib/files")
local cases = require("../../lib/cases")
local definitions = cases.read("ci/validation/tests/artifacts.cases.json")
local root = definitions.root

for _, case in definitions.cases do
    files.reset(root)
    local contents = table.clone(definitions.baseline.files)
    for name, value in case.files do
        contents[name] = value
    end
    for name, value in contents do
        fs.writeFile(root .. "/" .. name, value)
    end
    local manifest = {}
    for _, entry in case.manifest or definitions.baseline.manifest do
        table.insert(
            manifest,
            { path = entry.path, sha256 = serde.hash("sha256", entry.hash_contents) }
        )
    end
    fs.writeFile(root .. "/manifest.json", serde.encode("json", manifest))
    cases.check(case.name, case.valid, function()
        artifacts.verify(root)
        return true
    end)
end
files.reset(root)
print("Artifact data cases passed")
