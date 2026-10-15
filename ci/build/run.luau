-- ci/build/run.luau
--!strict
local Process = require("@lune/process")
local Config = require("../lib/config")
local config = Config.Read()
local Catalogue = require("../lib/catalogue")
local name = Process.env.CI_BUILD_TARGET or Catalogue.Targets(config)[1].name
if Process.env.CI_BUILD_SPEC then
    local entry = require("@lune/serde").decode("json", Process.env.CI_BUILD_SPEC) :: Config.BuildSpec
    config.build = entry.build
    require("./execute")(config, entry)
else
    require("./execute")(config, Catalogue.Target(config, name))
end
