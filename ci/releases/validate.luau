-- ci/releases/validate.luau
--!strict
local Fs = require("@lune/fs")
local Process = require("@lune/process")
local Serde = require("@lune/serde")
local Inputs = require("../lib/inputs")

-- Inspect proposed configuration as data using the trusted controller parser.
local previousRef = Inputs.ref
Inputs.ref = Process.env.CI_TESTED_SHA or previousRef
local document = Serde.decode("toml", Inputs.Read("ci/releases/versions.toml")) :: { releases: { { notes: string? } } }
local source = Process.exec("git", { "rev-parse", "HEAD" })
assert(source.ok, "cannot resolve trusted source controller")
Fs.writeDir("build/tmp/releases")
Fs.writeFile("build/tmp/releases/validation.json", Serde.encode("json", {
    versions = document, source_tip = source.stdout:gsub("%s+$", ""),
}))
local validation = Process.exec("node", { "ci/releases/cli.mjs", "validate" })
assert(validation.ok, "invalid version selections: " .. validation.stdout .. validation.stderr)
for _, release in document.releases do
    if release.notes then Inputs.Read(release.notes) end
end
Inputs.ref = previousRef
print("Explicit release version selections passed")
