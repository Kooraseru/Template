-- ci/releases/build.luau
--!strict
local Process = require("@lune/process")
local config = require("../lib/config").Read()
assert(config.release.enabled, "release generation is disabled")
local result = Process.exec("node", { "ci/releases/cli.mjs", "assemble" }, { stdio = "inherit" })
assert(result.ok, "release assembly failed: " .. result.stdout .. result.stderr)
