-- ci/build/tests/native-execute.luau
--!strict
local Fs = require("@lune/fs")
local Process = require("@lune/process")
local Serde = require("@lune/serde")
local config = require("../../lib/config").Read()
local definitions = Serde.decode("json", Fs.readFile("ci/releases/tests/cases.json")) :: { native_execution: { { argv: { string }, windows_argv: { string }, code: number, stdout_contains: string? } } }
config.build.commands = {}
config.build.package_paths = {}
local probes = {}
for _, definition in definitions.native_execution do
    table.insert(probes, { argv = if Process.os == "windows" then definition.windows_argv else definition.argv,
        code = definition.code, stdout_contains = definition.stdout_contains })
end
require("../execute")(config, { name = "native-checkout-fixture", runner = config.build.runner, probes = probes })
