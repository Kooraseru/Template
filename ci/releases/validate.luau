--!strict
local fs = require("@lune/fs")
local process = require("@lune/process")
local serde = require("@lune/serde")
local inputs = require("../lib/inputs")

-- Inspect proposed configuration as data using the trusted controller parser.
local previousRef = inputs.ref
inputs.ref = process.env.CI_TESTED_SHA or previousRef
local document = serde.decode("toml", inputs.read("ci/releases/versions.toml"))
local source = process.exec("git", { "rev-parse", "HEAD" })
assert(source.ok, "cannot resolve trusted source controller")
fs.writeDir("build/tmp/releases")
fs.writeFile("build/tmp/releases/validation.json", serde.encode("json", {
    versions = document, source_tip = source.stdout:gsub("%s+$", ""),
}))
local validation = process.exec("node", { "ci/releases/cli.mjs", "validate" })
assert(validation.ok, "invalid version selections: " .. validation.stdout .. validation.stderr)
for _, release in document.releases do
    if release.notes then inputs.read(release.notes) end
end
inputs.ref = previousRef
print("Explicit release version selections passed")
