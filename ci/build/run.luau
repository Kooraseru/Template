--!strict
local process = require("@lune/process")
local config = require("../lib/config").read()
local catalogue = require("../lib/catalogue")
local name = process.env.CI_BUILD_TARGET or catalogue.targets(config)[1].name
if process.env.CI_BUILD_SPEC then
    local entry = require("@lune/serde").decode("json", process.env.CI_BUILD_SPEC)
    config.build = entry.build
    require("./execute").run(config, entry)
else
    require("./execute").run(config, catalogue.target(config, name))
end
