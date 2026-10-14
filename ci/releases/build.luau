--!strict
local process = require("@lune/process")
local config = require("../lib/config").read()
assert(config.release.enabled, "release generation is disabled")
local result = process.exec("node", { "ci/releases/cli.mjs", "assemble" }, { stdio = "inherit" })
assert(result.ok, "release assembly failed: " .. result.stdout .. result.stderr)
