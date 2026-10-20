-- fabricator/tests/coverage.luau
--!strict

local Test = require("@testing")

--# Modules

local Coverage = require("../coverage")
local Gate = require("../../.github/integration/gate")
local Request = require("../../.github/integration/request")

--# Helpers

local function available(runner: string): boolean
	if runner == "failed-build" or runner == "unavailable-build" then
		local unavailable = runner == "unavailable-build"
		local errors = Gate.Check(Request.Normalize({}, false), {
			validate = { result = "success" },
			build = { result = if unavailable then "skipped" else "failure" },
		}, {}, { context = { ["local"] = true }, local_executing = if unavailable then 0 else 1 }, "push")
		return #errors == 0
	end
	return Coverage.Local({ runner = runner }).Execute
end

--# Declaration

local definition: Test.Definition<string, boolean> = {
	Name = "Local runner availability",
	Execute = available,
	Cases = {
		{ Name = "Runnable build failure remains an error", Input = "failed-build", Expected = false },
		{ Name = "Unavailable native coverage may be skipped", Input = "unavailable-build", Expected = true },
		{ Name = "Linux Docker runner executes", Input = "ubuntu-latest", Expected = true },
		{ Name = "ARM Linux Docker runner executes", Input = "ubuntu-24.04-arm", Expected = true },
		{ Name = "macOS is unverified without native runner", Input = "macos-15", Expected = false },
		{ Name = "Windows native runner is unavailable through act", Input = "windows-11-arm", Expected = false },
	},
}

return Test.new(definition)
