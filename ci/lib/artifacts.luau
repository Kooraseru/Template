--!strict
local fs = require("@lune/fs")
local serde = require("@lune/serde")
local config = require("./config")
local artifacts = {}
local rules = require("./rules")
local definition = rules.read("ci/distribution/manifest.rules.json")
function artifacts.verify(root: string)
    local manifest = serde.decode("json", fs.readFile(root .. "/" .. definition.manifest_file))
    rules.validate(manifest, definition)
    local seen = {}
    for _, entry in manifest do
        local path = config.relative(entry.path)
        seen[path] = true
        assert(fs.isFile(root .. "/" .. path), "missing artifact: " .. path)
        assert(
            serde.hash(definition.hash_algorithm, fs.readFile(root .. "/" .. path))
                == entry[definition.hash_field],
            "artifact checksum mismatch: " .. path
        )
    end
    local function inspect(directory: string, prefix: string)
        for _, name in fs.readDir(directory) do
            local path = prefix .. name
            if fs.isDir(directory .. "/" .. name) then
                inspect(directory .. "/" .. name, path .. "/")
            else
                assert(
                    path == definition.manifest_file or seen[path],
                    "unlisted artifact: " .. path
                )
            end
        end
    end
    inspect(root, "")
end
return artifacts
