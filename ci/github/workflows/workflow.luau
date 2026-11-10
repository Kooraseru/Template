-- ci/github/workflows/workflow.luau
--!strict

local Configuration = require("@ci/github/configuration")
local Process = require("@lute/process")
local Json = require("@formats/json")
local Contract = require("@ci/bootstrap/contracts/contract")
local NativeJob = require("@ci/github/workflows/nativeJob")

local Workflow = {}

type Step = NativeJob.Step

local function appendStep(steps: { Step }, step: Step): ()
	table.insert(steps, step)
end

function Workflow.JobId(identity: string): string
	return "component_" .. Contract.Key(identity)
end

-- This consumes the scheduler's validated tasks, not a second component list.
local function credentialBindings(name: string, bindings: { [string]: string }): { [string]: string }
	local environment = { CI_CREDENTIAL_ENVIRONMENT = name }
	for role, alias in bindings do
		environment["CI_CREDENTIAL_" .. role:upper()] = "${{ " .. alias .. " }}"
	end
	return environment
end

local function componentEnvironment(configuration: Configuration.Configuration, profile: Configuration.Profile, task: Contract.Task): string
	local match: string? = nil
	for name, bindings in configuration.environments do
		if name == profile.bootstrapEnvironment or name == profile.reportingEnvironment then
			continue
		end
		local count = 0
		for _ in bindings do
			count += 1
		end
		if count ~= #task.credentials then
			continue
		end
		local covers = true
		for _, role in task.credentials do
			covers = covers and bindings[role] ~= nil
		end
		if covers then
			if match then
				error(`{task.identity}: ambiguous credential environments for {table.concat(task.credentials, ", ")}`, 0)
			end
			match = name
		end
	end
	return match or error(`{task.identity}: no credential environment for {table.concat(task.credentials, ", ")}`, 0)
end

function Workflow.Render(tasks: { Contract.Task }, sourceSha: string, branch: string, event: string): string
	if event == "pull_request" then
		for _, task in tasks do
			if task.boundary ~= "read" then
				error(`Refusing privileged task {task.identity} in PR CI Execution`, 0)
			end
		end
	end
	-- act's local artifact server implements the v4 artifact protocol.
	local uploadArtifact = if Process.env.ACT == "true"
		then "actions/upload-artifact@v4"
		else "actions/upload-artifact@v7"
	local downloadArtifact = if Process.env.ACT == "true"
		then "actions/download-artifact@v4"
		else "actions/download-artifact@v8"
	local configuration = Configuration.new()
	local profile = configuration.profiles["source-ci"]
	local hostedPush = event == "push" and Process.env.ACT ~= "true"
	if hostedPush and profile.credentialProvider ~= "environment" and profile.credentialProvider ~= "oidc" then
		error("Hosted execution requires environment or OIDC credential transport", 0)
	end
	local jobs: { [string]: unknown } = {}
	local identities: { [string]: Contract.Task } = {}
	local jobIds: { string } = {}
	for _, task in tasks do
		identities[task.identity] = task
	end

	for _, task in tasks do
		local needs: { string } = {}
		local steps: { Step } = {
			{
				uses = "actions/checkout@v7",
				["if"] = "${{ !env.ACT }}",
				with = { ref = sourceSha, ["fetch-depth"] = 0, ["persist-credentials"] = false },
			},
		}
		appendStep(steps, { uses = "actions/setup-node@v7.1.0", with = { ["node-version"] = "24" } })

		for _, dependency in task.needs do
			table.insert(needs, Workflow.JobId(dependency))
			local provider = identities[dependency]
			if not provider then
				error(`{task.identity}: unknown planned dependency {dependency}`, 0)
			end
			if #provider.outputs > 0 then
				appendStep(steps, {
					name = `Receive {dependency} outputs`,
					uses = downloadArtifact,
					with = { name = `ci-{Contract.Key(dependency)}`, path = "build/run/ci-execution/artifacts" },
				})
			end
		end

		local active = #task.credentials > 0 and hostedPush and profile.credentialProvider == "oidc"
		local environmentName: string? = nil
		local runEnvironment: { [string]: string } = {}
		if task.boundary == "privileged" then
			runEnvironment.GH_TOKEN = "${{ github.token }}"
		end
		if #task.credentials > 0 and hostedPush and profile.credentialProvider == "environment" then
			environmentName = componentEnvironment(configuration, profile, task)
			for key, value in credentialBindings(environmentName, configuration.environments[environmentName]) do
				runEnvironment[key] = value
			end
		end
		if active then
			appendStep(steps, {
				name = "Install dependencies",
				run = "node dependencies/packages/core/dependencyLoader/index.ts",
			})
			runEnvironment.CI_SELECTOR_ROLES = table.concat(task.credentials, ",")
		end

		appendStep(steps, {
			name = `Run {task.identity}`,
			id = "component",
			env = if next(runEnvironment) then runEnvironment else nil,
			run = if active then `build/dependencies/bin/lute/lute run ci/entry.luau --component {task.identity}`
				else `bash ci/github/workflows/run-logged.sh ci-execution {Contract.Key(
				task.identity
			)} --component {task.identity}`,
		})
		if #task.outputs > 0 then
			appendStep(steps, {
				name = `Publish {task.identity} outputs`,
				["if"] = "${{ steps.component.outputs.skipped != toJSON(true) }}",
				uses = uploadArtifact,
				with = {
					name = `ci-{Contract.Key(task.identity)}`,
					path = `build/run/ci-execution/artifacts/{Contract.Key(task.identity)}.tar`,
					["if-no-files-found"] = "error",
				},
			})
		end

		local job: { [string]: unknown } = {
			name = task.identity,
			env = { CI_COMPONENT = task.identity },
			["runs-on"] = "ubuntu-latest",
			steps = steps,
			outputs = {
				outcome = "${{ steps.component.outputs.outcome }}",
				skipped = "${{ steps.component.outputs.skipped }}",
			},
		}
		if task.boundary == "privileged" then
			job.permissions = { contents = "write" }
		end
		local nativeStart = #steps + 1
		NativeJob.Configure(task.identity, task.boundary, steps, job)
		if environmentName then
			if job.environment then
				error(`{task.identity}: credential environment conflicts with native job environment`, 0)
			end
			job.environment = { name = environmentName, deployment = false }
		end
		if active then
			local permissions = (job.permissions or { contents = "read" }) :: { [string]: string }
			permissions["id-token"] = "write"
			job.permissions = permissions
		end

		if Process.env.ACT == "true" then
			for index = nativeStart, #steps do
				local step = steps[index]
				if step.uses then
					-- act preloads actions even when their condition skips them.
					-- Do not load or run GitHub-only native adapters locally.
					step.uses = nil
					step.with = nil
					step.run = "node dependencies/packages/core/dependencyLoader/index.ts --exec luau.lute --version"
					step["if"] = "${{ !env.ACT }}"
				end
			end
		end

		appendStep(steps, {
			name = "Collect component logs",
			["if"] = "${{ always() }}",
			uses = uploadArtifact,
			with = {
				name = `ci-logs-{Contract.Key(task.identity)}`,
				path = "build/run/ci-execution/logs/",
				["if-no-files-found"] = "ignore",
			},
		})
		appendStep(steps, {
			name = "Collect response fragments",
			["if"] = "${{ always() }}",
			uses = uploadArtifact,
			with = {
				name = `ci-response-{Contract.Key(task.identity)}`,
				path = "build/run/ci-execution/responses/",
				["if-no-files-found"] = "ignore",
			},
		})
		if #needs > 0 then
			job.needs = needs
			job["if"] = "${{ success() && !contains(needs.*.outputs.skipped, toJSON(true)) }}"
		end
		local jobId = Workflow.JobId(task.identity)
		jobs[jobId] = job
		table.insert(jobIds, jobId)
	end

	local reportEnvironment = if hostedPush then profile.reportingEnvironment else nil
	local reportBindings = if reportEnvironment
		then credentialBindings(reportEnvironment, configuration.environments[reportEnvironment])
		else {} :: { [string]: string }
	reportBindings.CI_JOB_RESULTS = "${{ toJSON(needs) }}"
	reportBindings.CI_RESPONSE_DOWNLOAD_OUTCOME = "${{ steps.responses.outcome }}"
	reportBindings.GH_TOKEN = "${{ github.token }}"
	jobs.report = {
		environment = if reportEnvironment then { name = reportEnvironment, deployment = false } else nil,
		name = "CI result",
		permissions = { contents = "read", actions = "read" },
		env = { CI_COMPONENT = "response" },
		["runs-on"] = "ubuntu-latest",
		needs = if #jobIds > 0 then jobIds else nil,
		["if"] = "${{ always() }}",
		steps = {
			{
				uses = "actions/checkout@v7",
				["if"] = "${{ !env.ACT }}",
				with = { ref = sourceSha, ["persist-credentials"] = false },
			},
			{ uses = "actions/setup-node@v7.1.0", with = { ["node-version"] = "24" } },
			{
				name = "Receive component response fragments",
				id = "responses",
				uses = downloadArtifact,
				with = {
					pattern = "ci-response-*",
					["merge-multiple"] = true,
					path = "build/run/ci-execution/responses",
				},
			},
			{
				name = "Report component results",
				["if"] = "${{ always() }}",
				env = reportBindings,
				run = "bash ci/github/workflows/run-logged.sh ci-execution report --report",
			},
			{
				name = "Collect final report and logs",
				["if"] = "${{ always() }}",
				uses = uploadArtifact,
				with = {
					name = "ci-report",
					path = "build/run/ci-execution/responses/execution.md\nbuild/run/ci-execution/logs/",
					["if-no-files-found"] = "ignore",
				},
			},
		},
	}
	jobs.cleanup = {
		name = "Remove temporary CI branch",
		["runs-on"] = "ubuntu-latest",
		needs = { "report" },
		["if"] = "${{ always() }}",
		permissions = { contents = "write" },
		steps = {
			{
				uses = "actions/checkout@v7",
				["if"] = "${{ !env.ACT }}",
				with = { ref = sourceSha, ["persist-credentials"] = false },
			},
			{ uses = "actions/setup-node@v7.1.0", with = { ["node-version"] = "24" } },
			{
				name = "Delete temporary branch for this run",
				env = { GH_TOKEN = "${{ github.token }}" },
				run = "node dependencies/packages/core/dependencyLoader/index.ts --only workspace.npm --exec luau.lute run ci/entry.luau --cleanup-branch",
			},
		},
	}
	-- JSON is a YAML subset. Validate the document before adding its YAML comment header.
	local document = Json.encode({
		name = "CI Execution",
		["run-name"] = `CI Execution for {sourceSha:sub(1, 12)}`,
		on = { push = { branches = { branch } } },
		permissions = { contents = "read" },
		env = { CI_EVENT = event, CI_GRAPH_RUN = "true", CI_SOURCE_SHA = sourceSha, CI_RUN_BRANCH = branch },
		jobs = jobs,
	})
	Json.decode(document)
	return "# Generated by ci/github/workflows/workflow.luau; do not edit.\n" .. document
end

return Workflow
