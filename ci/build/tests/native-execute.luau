--!strict
local fs = require("@lune/fs")
local process = require("@lune/process")
local serde = require("@lune/serde")
local config = require("../../lib/config").read()
local definitions = serde.decode("json", fs.readFile("ci/releases/tests/cases.json"))
config.build.commands = {}
config.build.package_paths = {}
local probes = {}
for _, definition in definitions.native_execution do
    table.insert(probes, { argv = if process.os == "windows" then definition.windows_argv else definition.argv,
        code = definition.code, stdout_contains = definition.stdout_contains })
end
require("../execute").run(config, { name = "native-checkout-fixture", runner = config.build.runner, probes = probes })
