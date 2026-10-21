-- ci/fabricator/workflow.luau
--!strict

local Build = {}

--# Modules

local Process = require("@lune/process")
local Config = require("../libraries/registry/config")
local Catalogue = require("../libraries/registry/catalogue")
local Serde = require("@lune/serde")
local BuildExecutor = require("./execute")
local Targets = require("./targets")

--# Functions

function Build.Run()
	local config = Config.Read()
	local name = Process.env.CI_BUILD_TARGET or Catalogue.Targets(config)[1].name

	if Process.env.CI_BUILD_SPEC then
		local entry = Serde.decode("json", Process.env.CI_BUILD_SPEC) :: Config.BuildSpec
		config.build = entry.build
		config.targets = Targets.Validate(entry.project_targets or {})
		BuildExecutor.Run(config, entry)
	else
		Targets.Discover(config.targets)
		BuildExecutor.Run(config, Catalogue.Target(config, name))
	end
end

return Build
