-- repo/ci/bootstrap/init.luau
--!strict

local Executor = require("@self/execution/executor")
local Reporter = require("@self/outcomes/reporter")
local Discovery = require("@self/discovery")
local Planner = require("@self/planning")
local Contract = require("@self/contracts/contract")
local BranchRun = require("@ci/github/branches/branchRun")
local Credentials = require("@ci/github/authentication/credentials")
local TaskRunner = require("@ci/github/workflows/taskRunner")
local Publication = require("@ci/github/publication")

local Bootstrap = {}
Bootstrap.__index = Bootstrap

type BootstrapFields = {
	event: string,
	executor: Executor.Executor,
	reporter: Reporter.Reporter,
	discovery: Discovery.Discovery,
	planner: Planner.Planner,
	credentials: Credentials.Credentials,
}

export type Bootstrap = setmetatable<BootstrapFields, typeof(Bootstrap)>

function Bootstrap.new(event: string): Bootstrap
	local credentials = Credentials.new()
	local fields: BootstrapFields = {
		event = event,
		executor = Executor.new(credentials),
		reporter = Reporter.new(),
		discovery = Discovery.new(),
		planner = Planner.new(),
		credentials = credentials,
	}
	return setmetatable(fields, Bootstrap)
end

function Bootstrap.BuildPlan(self: Bootstrap): { Contract.Task }
	local components = self.discovery:Discover()
	return self.planner:Resolve(components, self.event)
end

function Bootstrap.Run(self: Bootstrap, component: string?, reportOnly: boolean?): ()
	local tasks = self:BuildPlan()
	if component or reportOnly then
		if component then
			TaskRunner.Run(tasks, self.event, component, self.credentials)
		else
			TaskRunner.Report(tasks)
		end
		return
	end

	if BranchRun.TryLaunch(tasks, self.event, self.credentials) then
		Publication.Output("delegated", "true")
		return
	end
	local result = self.executor:Execute(tasks, self.event)
	self.reporter:Report(result.outcomes, #tasks)
	if not result.passed then
		error("one or more discovered CI components failed or were blocked", 0)
	end
end

return Bootstrap
