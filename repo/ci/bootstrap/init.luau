-- repo/ci/bootstrap/init.luau
--!strict

local Executor = require("@self/execution/executor")
local Reporter = require("@self/outcomes/reporter")
local Preflight = require("@ci/preflight")
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
	preflight: Preflight.Preflight,
	credentials: Credentials.Credentials,
}

export type Bootstrap = setmetatable<BootstrapFields, typeof(Bootstrap)>

function Bootstrap.new(event: string): Bootstrap
	local credentials = Credentials.new()
	local fields: BootstrapFields = {
		event = event,
		executor = Executor.new(credentials),
		reporter = Reporter.new(),
		preflight = Preflight.new(),
		credentials = credentials,
	}
	return setmetatable(fields, Bootstrap)
end

function Bootstrap.Run(self: Bootstrap, preflightOnly: boolean?, component: string?, reportOnly: boolean?): ()
	if component or reportOnly then
		-- Native component and report jobs validate the plan without repeating editor analyzers.
		local plan = self.preflight:Plan(self.event)
		if not plan.available then
			local diagnostic = plan.diagnostics[1]
			error(if diagnostic then diagnostic.message else "CI component plan is unavailable", 0)
		end
		if component then
			TaskRunner.Run(plan.tasks, self.event, component, self.credentials)
		else
			TaskRunner.Report(plan.tasks)
		end
		return
	end

	local preflight = self.preflight:Run(self.event)
	if not preflight.passed then
		error("preflight found unreachable or invalid execution paths", 0)
	end
	if preflightOnly then
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
