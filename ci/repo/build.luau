--!strict
local fs = require("@lune/fs")
local process = require("@lune/process")
local serde = require("@lune/serde")
local config = require("../lib/config").read()
local files = require("../lib/files")
assert(config.repository.enabled, "repository generation is disabled")
files.reset("build/repo")
for _, path in config.repository.include do
    assert(fs.isDir(path) or fs.isFile(path), "missing publication input: " .. path)
    files.copy(path, "build/repo/" .. path, true)
end
for _, name in fs.readDir("ci/repo/templates") do
    files.copy("ci/repo/templates/" .. name, "build/repo/" .. name)
end
for _, name in { "LICENSE", "CITATION.cff" } do
    if fs.isFile(name) then
        files.copy(name, "build/repo/" .. name)
    end
end
fs.writeFile(
    "build/repo/publication.json",
    serde.encode("json", {
        source = process.env.GITHUB_SHA or "local",
        repository = process.env.GITHUB_REPOSITORY or "local",
    }, true)
)
print("Generated repository at build/repo")
