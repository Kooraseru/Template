-- ci/bootstrap/init.luau
--!strict

local Discovery = require("@self/discovery")
local Planner = require("@self/planning")
local Executor = require("@self/executor")
local Reporter = require("@self/reporter")

local Bootstrap = {}
Bootstrap.__index = Bootstrap

type BootstrapFields = {
	event: string,
	discovery: Discovery.Discovery,
	planner: Planner.Planner,
	executor: Executor.Executor,
	reporter: Reporter.Reporter,
}

export type Bootstrap = setmetatable<BootstrapFields, typeof(Bootstrap)>

function Bootstrap.new(event: string): Bootstrap
	local fields: BootstrapFields = {
		event = event,
		discovery = Discovery.new(),
		planner = Planner.new(),
		executor = Executor.new(),
		reporter = Reporter.new(),
	}
	return setmetatable(fields, Bootstrap)
end

function Bootstrap.Run(self: Bootstrap): ()
	local contracts = self.discovery:Discover()
	local tasks = self.planner:Resolve(contracts, self.event)
	local result = self.executor:Execute(tasks, self.event)
	self.reporter:Report(result.outcomes, #tasks)
	if not result.passed then
		error("one or more discovered CI components failed or were blocked", 0)
	end
end

return Bootstrap
