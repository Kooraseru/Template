-- ci/bootstrap/stages.luau
--!strict

local Fs = require("@std/fs")
local Process = require("@lute/process")
local Bootstrap = require("@ci/bootstrap")
local Configuration = require("@ci/github/configuration")
local Credentials = require("@ci/github/authentication/credentials")
local Workflow = require("@ci/github/workflows/workflow")
local TaskRunner = require("@ci/github/workflows/taskRunner")
local Artifacts = require("@ci/github/workflows/artifacts")
local Contract = require("@ci/bootstrap/contracts/contract")
local SkipPolicy = require("@ci/bootstrap/outcomes/skipPolicy")
local Reporter = require("@ci/bootstrap/outcomes/reporter")

local Stages = {}

local function trustedSource(): ()
	if Process.env.ACT == "true" or Process.env.GITHUB_ACTIONS ~= "true"
		or Process.env.GITHUB_REF ~= "refs/heads/source"
		or (Process.env.GITHUB_EVENT_NAME ~= "push" and Process.env.GITHUB_EVENT_NAME ~= "workflow_dispatch") then
		error("Publication is restricted to trusted source runs", 0)
	end
end

local function publishGroup(task: Contract.Task, configuration: Configuration.Configuration): string
	if #task.credentials == 0 then
		return "general"
	end
	local profile = configuration.profiles["source-ci"]
	return Workflow.ComponentEnvironment(configuration, profile, task)
end

local function expectedGroups(configuration: Configuration.Configuration): { [string]: boolean }
	local expected: { [string]: boolean } = { general = true }
	local profile = configuration.profiles["source-ci"]
	for name in configuration.environments do
		if name ~= profile.bootstrapEnvironment and name ~= profile.reportingEnvironment then
			expected[name] = true
		end
	end
	return expected
end

function Stages.Run(phase: string, event: string): ()
	if phase ~= "build" and phase ~= "publish" then
		error("Unsupported CI stage", 0)
	end
	if phase == "publish" then
		trustedSource()
	end
	local tasks = Bootstrap.Plan(event)
	local configuration = Configuration.new()
	local group = Process.env.CI_PUBLISH_GROUP
	local selected: { Contract.Task } = {}
	local roles: { string } = {}
	local allowed = if phase == "publish" then expectedGroups(configuration) else {}

	if phase == "publish" and (not group or not allowed[group]) then
		error("Unknown publication credential group", 0)
	end

	for _, task in tasks do
		if task.phase ~= phase then
			continue
		end
		if phase == "publish" and publishGroup(task, configuration) ~= group then
			continue
		end
		table.insert(selected, task)
		for _, role in task.credentials do
			if not table.find(roles, role) then
				table.insert(roles, role)
			end
		end
	end

	table.sort(roles)
	local credentials: Credentials.Credentials? = nil
	if phase == "publish" and #roles > 0 then
		-- The credential selector is scoped to this job's components, not to all publication roles.
		Process.env.CI_SELECTOR_ROLES = table.concat(roles, ",")
		credentials = Credentials.new(nil)
	end

	for _, task in selected do
		print(`::group::{task.identity}`)
		TaskRunner.Run(tasks, event, task.identity, credentials)
		print("::endgroup::")
		if phase == "publish" then
			local source = `{Artifacts.Transport()}/{Contract.Key(task.identity)}`
			local destination = `{Artifacts.Stage("publish")}/{group}/{Contract.Key(task.identity)}`
			Fs.createDirectory(`{Artifacts.Stage("publish")}/{group}`, { makeParents = true })
			local copied = Process.run({ "cp", "-a", source, destination })
			if not copied.ok then
				error(`Unable to stage publication record for {task.identity}`, 0)
			end
		end
	end
	print(`::notice::{phase} completed {#selected} components`)
end

function Stages.Report(event: string): ()
	trustedSource()
	local tasks = Bootstrap.Plan(event)
	local configuration = Configuration.new()
	local groups = expectedGroups(configuration)
	local outcomes: { [string]: string } = {}
	local passed = true
	Process.env.CI_SELECTOR_ROLES = "app_id,app_private_key"
	local credentials = Credentials.new(nil)
	for _, task in tasks do
		if task.phase ~= "publish" then
			continue
		end
		local group = publishGroup(task, configuration)
		if not groups[group] then
			error(`Publication group {group} is not available`, 0)
		end
		local ok, outcome = pcall(TaskRunner.Verify, task)
		if not ok then
			outcomes[task.identity] = "failed"
			print(`::error::{task.identity}: missing or invalid publication record`)
			passed = false
			continue
		end
		outcomes[task.identity] = outcome
		if outcome == "skipped" then
			local conclusion = SkipPolicy.Conclusion(task.identity)
			if conclusion == "failure" then
				passed = false
			elseif conclusion == "neutral" then
				local reported, problem = pcall(SkipPolicy.ReportNeutral, task.identity, credentials)
				if not reported then
					print(`::error::{task.identity}: {problem}`)
					outcomes[task.identity] = "skipped (neutral Check Run failed)"
					passed = false
				end
			end
		end
	end
	Reporter.new():Report(outcomes, #tasks, not passed)
	if not passed then
		error("Publication did not complete successfully", 0)
	end
end

return Stages
