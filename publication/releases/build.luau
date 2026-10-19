-- publication/releases/build.luau
--!strict

local ReleaseBuild = {}

--# Modules

local Process = require("@lune/process")
local Config = require("../../libraries/registry/config")

--# Functions

function ReleaseBuild.Run()
	local config = Config.Read()

	assert(config.release.enabled, "release generation is disabled")
	local result = Process.exec("node", { "publication/releases/cli.mjs", "assemble" }, { stdio = "inherit" })

	assert(result.ok, "release assembly failed: " .. result.stdout .. result.stderr)
end

return ReleaseBuild
