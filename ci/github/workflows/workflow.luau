-- ci/github/workflows/workflow.luau
--!strict

local Configuration = require("@ci/github/configuration")
local Process = require("@lute/process")
local Json = require("@formats/json")
local Contract = require("@ci/bootstrap/contracts/contract")
local SkipPolicy = require("@ci/bootstrap/outcomes/skipPolicy")
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
	local jobs: { [string]: unknown } = {}
	local identities: { [string]: Contract.Task } = {}
	local jobIds: { string } = {}
	for _, task in tasks do
		identities[task.identity] = task
	end

	for _, task in tasks do
		local needs: { string } = {}
		local credentialRoles = table.clone(task.credentials)
		if SkipPolicy.Conclusion(task.identity) == "neutral" then
			table.insert(credentialRoles, "app_id")
			table.insert(credentialRoles, "app_private_key")
		end
		local steps: { Step } = {
			{
				uses = "actions/checkout@v7",
				["if"] = "${{ !env.ACT }}",
				with = { ref = sourceSha, ["fetch-depth"] = 0, ["persist-credentials"] = false },
			},
		}
		appendStep(steps, { uses = "actions/setup-node@v4", with = { ["node-version"] = "24" } })

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

		local profile = configuration.profiles["source-ci"]
		-- The selector needs the Actions inventory to discover capability-based credentials.
		local active = #credentialRoles > 0 and Process.env.ACT ~= "true"
			and (profile.credentialProvider == "oidc" or profile.usesCommands or profile.githubContext)
		local oidc = active and profile.credentialProvider == "oidc"
		local credentialEnvironment: { [string]: string } = {}
		if active then
			appendStep(steps, {
				name = "Install dependencies",
				run = "node dependencies/packages/core/dependencyLoader/index.ts",
			})
			credentialEnvironment.CI_SELECTOR_ROLES = table.concat(credentialRoles, ",")
			if profile.githubContext then
				credentialEnvironment.CI_SECRETS = "${{ toJSON(secrets) }}"
				credentialEnvironment.CI_VARIABLES = "${{ toJSON(vars) }}"
			end
		end
		if #credentialRoles > 0 then
			appendStep(steps, {
				name = "Resolve credential names",
				id = "credentials",
				run = "node dependencies/packages/core/dependencyLoader/index.ts --exec luau.lute run ci/entry.luau --credential-names",
			})
			for _, role in credentialRoles do
				local entry = configuration.roles[role]
				if entry.selection == "named" or entry.fallbackName then
					local output = "steps.credentials.outputs." .. role
					local bindings: { string } = {}
					for _, source in entry.sources do
						local context = if source == "secret" then "secrets" else "vars"
						table.insert(bindings, context .. "[" .. output .. "]")
					end
					credentialEnvironment["CI_CREDENTIAL_" .. role:upper()] = "${{ " .. table.concat(bindings, " || ") .. " }}"
				end
			end
		end

		appendStep(steps, {
			name = `Run {task.identity}`,
			id = "component",
			env = if task.boundary == "privileged"
				then {
					GH_TOKEN = "${{ github.token }}",
				}
				else nil,
			run = if active then `build/dependencies/bin/lute/lute run ci/entry.luau --component {task.identity}`
				else `bash ci/github/workflows/run-logged.sh ci-execution {Contract.Key(
				task.identity
			)} --component {task.identity}`,
		})
		local runStep = steps[#steps]

		if #credentialRoles > 0 then
			local environment = runStep.env or {}
			for name, value in credentialEnvironment do
				environment[name] = value
			end
			runStep.env = environment
		end

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
		if oidc then
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

	jobs.report = {
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
			{ uses = "actions/setup-node@v4", with = { ["node-version"] = "24" } },
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
				env = {
					CI_JOB_RESULTS = "${{ toJSON(needs) }}",
					CI_RESPONSE_DOWNLOAD_OUTCOME = "${{ steps.responses.outcome }}",
					GH_TOKEN = "${{ github.token }}",
				},
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
			{ uses = "actions/setup-node@v4", with = { ["node-version"] = "24" } },
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
