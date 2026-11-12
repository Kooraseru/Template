-- ci/bootstrap/init.luau
--!strict

local Process = require("@lute/process")
local Executor = require("@self/execution/executor")
local Reporter = require("@self/outcomes/reporter")
local Discovery = require("@self/discovery")
local Planner = require("@self/planning")
local Contract = require("@self/contracts/contract")
local BranchRun = require("@ci/github/resources/branches/branchRun")
local Credentials = require("@ci/github/authentication/credentials")
local TaskRunner = require("@ci/github/workflows/taskRunner")
local Publication = require("@ci/github/publication")

local Configuration = require("@ci/github/configuration")

local Bootstrap = {}
Bootstrap.__index = Bootstrap

type BootstrapFields = {
	event: string,
	profile: Configuration.Profile?,
	executor: Executor.Executor,
	reporter: Reporter.Reporter,
	discovery: Discovery.Discovery,
	planner: Planner.Planner,
	credentials: Credentials.Credentials,
}

export type Bootstrap = setmetatable<BootstrapFields, typeof(Bootstrap)>

function Bootstrap.new(event: string, profile: Configuration.Profile?): Bootstrap
	local credentials = Credentials.new(profile)
	local fields: BootstrapFields = {
		event = event,
		profile = profile,
		executor = Executor.new(credentials),
		reporter = Reporter.new(),
		discovery = Discovery.new(),
		planner = Planner.new(),
		credentials = credentials,
	}
	return setmetatable(fields, Bootstrap)
end

function Bootstrap.Plan(event: string): { Contract.Task }
	local components = Discovery.new():Discover()
	local tasks = Planner.new():Resolve(components, event)
	local roles = Configuration.new().roles
	for _, task in tasks do
		for _, role in task.credentials do
			if not roles[role] then
				error(`{task.identity}: unknown credential role {role}`, 0)
			end
		end
	end
	return tasks
end

function Bootstrap.BuildPlan(self: Bootstrap): { Contract.Task }
	return Bootstrap.Plan(self.event)
end

function Bootstrap.Run(self: Bootstrap, component: string?, reportOnly: boolean?, profileName: string?): ()
	local tasks = self:BuildPlan()
	if reportOnly then
		local phase = if Process.env.CI_PHASE == "publish" then "publish" else "build"
		local selected: { Contract.Task } = {}
		for _, task in tasks do if task.phase == phase then table.insert(selected, task) end end
		tasks = selected
	end
	if component or reportOnly then
		if component then
			TaskRunner.Run(tasks, self.event, component, self.credentials)
		else
			TaskRunner.Report(tasks, self.credentials)
		end
		return
	end

	local restriction: ("validate" | "source-ci")? = nil
	if self.profile then
		restriction = if profileName == "source-ci" then "source-ci" else "validate"
	end
	if Process.env.ACT == "true" and Process.env.CI_GRAPH_RUN ~= "true" then
		if BranchRun.TryLaunch(tasks, self.event, self.credentials) then return end
	end
	if restriction ~= "validate" and (not self.profile or self.profile.delegate) then
		if restriction == "source-ci" and not (Process.env.ACT == "true") then
			if not BranchRun.TryLaunch(tasks, self.event, self.credentials) then
				error("Source CI delegation is unavailable; privileged components cannot execute in Bootstrap", 0)
			end
			Publication.Output("delegated", "true")
			return
		elseif BranchRun.TryLaunch(tasks, self.event, self.credentials) then
			Publication.Output("delegated", "true")
			return
		end
	end
	local result = self.executor:Execute(tasks, self.event, restriction)
	self.reporter:Report(result.outcomes, #tasks, nil, restriction ~= nil)
	if not result.passed then
		error("one or more discovered CI components failed or were blocked", 0)
	end
end

return Bootstrap
