-- ci/publication/releases/build.luau
--!strict

local ReleaseBuild = {}

--# Modules

local Config = require("../../libraries/registry/config")
local Render = require("./render")
local Documents = require("../../libraries/bootstrap/documents")

--# Functions

function ReleaseBuild.Run()
	local config = Config.Read()

	assert(config.release.enabled, "release generation is disabled")
	Render.Assemble(Documents.Read("build/tmp/releases/plan.json"))
end

return ReleaseBuild
