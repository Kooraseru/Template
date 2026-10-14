--!strict
local fs = require("@lune/fs")
local serde = require("@lune/serde")
local configuration = require("../lib/config")
local config = configuration.read()
local files = require("../lib/files")
local artifacts = require("../lib/artifacts")
local catalogue = require("../lib/catalogue")
assert(config.release.enabled, "release generation is disabled")
local version = config.release.version
local record = "ci/releases/records/" .. version .. ".md"
assert(fs.isFile(record), "release requires an authored record: " .. record)
files.reset("build/releases")
local entries = catalogue.targets(config)
for _, entry in entries do
    local source = "build/distributions/distribution-" .. entry.name
    artifacts.verify(source)
    files.copy(source, "build/releases/packages/" .. entry.name)
end
files.copy(record, "build/releases/notes.md")
fs.writeFile("build/releases/release.json", serde.encode("json", { version = version }, true))
print("Generated release " .. version)
