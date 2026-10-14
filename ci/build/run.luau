--!strict
local process = require("@lune/process")
local config = require("../lib/config").read()
local catalogue = require("../lib/catalogue")
local name = process.env.CI_BUILD_TARGET or catalogue.targets(config)[1].name
require("./execute").run(config, catalogue.target(config, name))
