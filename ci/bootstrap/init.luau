-- ci/bootstrap/init.luau
--!strict

local Executor = require("@self/executor")
local Reporter = require("@self/reporter")
local Preflight = require("./preflight")

local Bootstrap = {}
Bootstrap.__index = Bootstrap

type BootstrapFields = {
	event: string,
	executor: Executor.Executor,
	reporter: Reporter.Reporter,
	preflight: Preflight.Preflight,
}

export type Bootstrap = setmetatable<BootstrapFields, typeof(Bootstrap)>

function Bootstrap.new(event: string): Bootstrap
	local fields: BootstrapFields = {
		event = event,
		executor = Executor.new(),
		reporter = Reporter.new(),
		preflight = Preflight.new(),
	}
	return setmetatable(fields, Bootstrap)
end

function Bootstrap.Run(self: Bootstrap, preflightOnly: boolean?): ()
	local preflight = self.preflight:Run(self.event)
	if not preflight.passed then
		error("preflight found unreachable or invalid execution paths", 0)
	end
	if preflightOnly then
		return
	end
	local result = self.executor:Execute(preflight.tasks, self.event)
	self.reporter:Report(result.outcomes, #preflight.tasks)
	if not result.passed then
		error("one or more discovered CI components failed or were blocked", 0)
	end
end

return Bootstrap
