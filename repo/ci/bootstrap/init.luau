-- repo/ci/bootstrap/init.luau
--!strict

local Executor = require("@self/executor")
local Reporter = require("@self/reporter")
local Preflight = require("./preflight")
local BranchRun = require("@ci/github/branchRun")
local Credentials = require("@ci/github/credentials")
local TaskRunner = require("@ci/github/taskRunner")
local Publication = require("@ci/github/publication")

local Bootstrap = {}
Bootstrap.__index = Bootstrap

type BootstrapFields = {
	event: string,
	executor: Executor.Executor,
	reporter: Reporter.Reporter,
	preflight: Preflight.Preflight,
	credentials: Credentials.Credentials,
}

export type Bootstrap = setmetatable<BootstrapFields, typeof(Bootstrap)>

function Bootstrap.new(event: string): Bootstrap
	local fields: BootstrapFields = {
		event = event,
		executor = Executor.new(),
		reporter = Reporter.new(),
		preflight = Preflight.new(),
		credentials = Credentials.new(),
	}
	return setmetatable(fields, Bootstrap)
end

function Bootstrap.Run(self: Bootstrap, preflightOnly: boolean?, component: string?, reportOnly: boolean?): ()
	local preflight = self.preflight:Run(self.event)
	if not preflight.passed then
		error("preflight found unreachable or invalid execution paths", 0)
	end
	if preflightOnly then
		return
	end
	if component then
		TaskRunner.Run(preflight.tasks, self.event, component)
		return
	end
	if reportOnly then
		TaskRunner.Report(preflight.tasks)
		return
	end
	if BranchRun.TryLaunch(preflight.tasks, self.event, self.credentials) then
		Publication.Output("delegated", "true")
		return
	end
	local result = self.executor:Execute(preflight.tasks, self.event)
	self.reporter:Report(result.outcomes, #preflight.tasks)
	if not result.passed then
		error("one or more discovered CI components failed or were blocked", 0)
	end
end

return Bootstrap
