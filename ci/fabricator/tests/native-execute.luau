-- ci/fabricator/tests/native-execute.luau
--!strict

local NativeExecutionTests = {}

--# Modules

local Fs = require("@lune/fs")
local Process = require("@lune/process")
local Serde = require("@lune/serde")
local Config = require("../../libraries/registry/config")
local BuildExecutor = require("../execute")

--# Functions

function NativeExecutionTests.Run()
	local config = Config.Read()
	local definitions = Serde.decode("json", Fs.readFile("ci/fabricator/ruleset.json")) :: {
		native: { cases: { { argv: { string }, windows_argv: { string }, code: number, stdout_contains: string? } } },
	}
	config.build.commands = {}
	config.build.package_paths = {}
	local probes = {}

	for _, definition in definitions.native.cases do
		table.insert(probes, {
			argv = if Process.os == "windows" then definition.windows_argv else definition.argv,
			code = definition.code,
			stdout_contains = definition.stdout_contains,
		})
	end
	BuildExecutor.Run(config, { name = "native-checkout-fixture", runner = config.build.runner, probes = probes })
end

return NativeExecutionTests
