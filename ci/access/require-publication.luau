-- ci/access/require-publication.luau
--!strict
local Process = require("@lune/process")
local Context = require("./context")
local Policy = require("./policy")
local Rules = require("../lib/rules")

assert(Policy.CanPublish(Context.Read(Process.env)), "publication context is not eligible")
Rules.Validate(Process.env, Rules.Read("ci/access/operation.rules.json"))
local protection = Process.exec("node", {
    "ci/releases/cli.mjs", "protect", assert(Process.env.GITHUB_REPOSITORY),
}, { stdio = "inherit" })
assert(protection.ok, "repository source protection is required for publication")
