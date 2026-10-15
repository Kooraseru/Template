-- ci/repo/build.luau
--!strict
local Fs = require("@lune/fs")
local Process = require("@lune/process")
local Serde = require("@lune/serde")
local config = require("../lib/config").Read()
local Files = require("../lib/files")
assert(config.repository.enabled, "repository generation is disabled")
Files.Reset("build/repo")
for _, path in config.repository.include do
    assert(Fs.isDir(path) or Fs.isFile(path), "missing publication input: " .. path)
    Files.Copy(path, "build/repo/" .. path, true)
end
for _, name in Fs.readDir("ci/repo/templates") do
    Files.Copy("ci/repo/templates/" .. name, "build/repo/" .. name)
end
for _, name in { "LICENSE", "CITATION.cff" } do
    if Fs.isFile(name) then
        Files.Copy(name, "build/repo/" .. name)
    end
end
Fs.writeFile(
    "build/repo/publication.json",
    Serde.encode("json", {
        source = Process.env.GITHUB_SHA or "local",
        repository = Process.env.GITHUB_REPOSITORY or "local",
    }, true)
)
print("Generated repository at build/repo")
