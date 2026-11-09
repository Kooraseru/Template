-- ci/github/resources/branches/branchRun.luau
--!strict

local Fs = require("@std/fs")
local Json = require("@formats/json")
local Net = require("@lute/net/client")
local Process = require("@lute/process")
local Task = require("@std/task")
local Contract = require("@ci/bootstrap/contracts/contract")
local Authentication = require("@ci/github/authentication/authentication")
local Configuration = require("@ci/github/configuration")
local Credentials = require("@ci/github/authentication/credentials")
local Workflow = require("@ci/github/workflows/workflow")
local TokenPermissions = require("@ci/github/authentication/tokenPermissions")
local Responses = require("@ci/github/reporting/responses")

local GitFailure = require("@ci/github/publication/gitFailure")

local BranchRun = {}
const PR_EXECUTION_TIMEOUT_SECONDS = 3600
const PR_EXECUTION_START_TIMEOUT_SECONDS = 120
const PR_EXECUTION_POLL_SECONDS = 8

local function git(arguments: { string }, cwd: string?, token: string?): string
	local command = table.clone(arguments)
	table.insert(command, 1, "git")
	local environment = table.clone(Process.env)

	if token then
		environment.CI_GIT_BOOTSTRAP_TOKEN = token
		environment.CI_GIT_SERVER_URL = Process.env.GITHUB_SERVER_URL or "https://github.com"
		environment.GIT_TERMINAL_PROMPT = "0"
	end

	local result = Process.run(command, {
		cwd = cwd,
		env = environment,
	})

	if not result.ok then
		error(
			`GitHub branch bootstrap Git operation failed with exit code {result.exitcode}: {GitFailure(result.stderr)}`,
			0
		)
	end
	return (result.stdout:gsub("%s+$", ""))
end

--[[
	Renders the native workflow at the source commit and pushes it from a detached worktree. The worktree is removed even if locking, committing, or pushing fails.
]]
local function launch(
	tasks: { Contract.Task },
	event: string,
	repository: string,
	branch: string,
	sha: string,
	access: Authentication.Access
): ()
	local runId = Process.env.GITHUB_RUN_ID
	local attempt = Process.env.GITHUB_RUN_ATTEMPT or "1"
	if not runId or not runId:match("^%d+$") or not attempt:match("^%d+$") then
		error("GitHub branch bootstrap requires a valid run ID and attempt", 0)
	end
	local worktree = `build/run/ci-start/artifacts/worktree-{runId}-{attempt}`
	if Fs.exists(worktree) then
		error("Refusing to reuse an existing bootstrap worktree", 0)
	end
	local valid = Process.run({ "git", "check-ref-format", `refs/heads/{branch}` })
	if not valid.ok then
		error("github.bootstrap.branch_prefix produced an invalid branch", 0)
	end
	local yaml = Workflow.Render(tasks, sha, branch, event)
	Fs.createDirectory("build/run/ci-start/artifacts", { makeParents = true })
	Fs.writeStringToFile("build/run/ci-start/artifacts/workflow.yml", yaml)
	git({ "worktree", "add", "--detach", worktree, sha })
	local stage = "writing generated workflow"
	local ok, failure = xpcall(function(): boolean
		Fs.createDirectory(`{worktree}/.github/workflows`, { makeParents = true })
		Fs.writeStringToFile(`{worktree}/.github/workflows/ci-execution.yml`, yaml)
		stage = "locking generated workflow dependencies"
		local loader = `{Process.cwd()}/dependencies/packages/core/dependencyLoader/index.ts`
		local locked = Process.run({ "node", loader, "--exec", "tools.actionsLock", "--no-interactive", "--no-narrow", ".github/workflows/ci-execution.yml" }, { cwd = worktree })
		if not locked.ok then
			error(`Official GitHub Actions lockfile generation failed: {locked.stderr}`, 0)
		end
		local verified = Process.run({ "node", loader, "--exec", "tools.actionsLock", "--verify-local", ".github/workflows/ci-execution.yml" }, { cwd = worktree })
		if not verified.ok then
			error(`Generated workflow is not covered by actions.lock: {verified.stderr}`, 0)
		end
		stage = "committing generated workflow"
		git({ "add", "--", ".github/workflows/ci-execution.yml", ".github/workflows/actions.lock" }, worktree)
		git({
			"-c",
			"user.name=CI bootstrap",
			"-c",
			"user.email=ci-bootstrap@users.noreply.github.com",
			"-c",
			"core.hooksPath=/dev/null",
			"commit",
			"--no-gpg-sign",
			"-m",
			`CI execution graph for {sha}`,
		}, worktree)
		stage = "pushing the CI execution branch"
		local server = Process.env.GITHUB_SERVER_URL or "https://github.com"
		git({
			"-c",
			"credential.helper=",
			"-c",
			"credential.helper=!bash ci/github/authentication/git-credential.sh",
			"push",
			"--porcelain",
			`{server}/{repository}.git`,
			`HEAD:refs/heads/{branch}`,
		}, worktree, access.token)
		return true
	end, tostring)
	local removed = Process.run({ "git", "worktree", "remove", "--force", worktree })
	if not removed.ok then
		print("::warning::Could not remove the temporary bootstrap worktree")
	end
	if not ok then
		error(`Native CI Execution launch failed while {stage}: {failure}`, 0)
	end
end

local function waitForPullRequestExecution(repository: string, branch: string): ()
	local token = Process.env.GH_TOKEN
	if not token or token == "" then
		error("PR gate needs the read-only GITHUB_TOKEN to observe native CI Execution", 0)
	end
	local api = Process.env.GITHUB_API_URL or "https://api.github.com"
	local encoded = branch:gsub("([^%w_.~-])", function(character: string): string
		return string.format("%%%02X", string.byte(character))
	end)
	local started = os.time()
	local observedId: number? = nil
	-- The required gate check must reflect the generated run, not merely its dispatch.
	while os.time() - started < PR_EXECUTION_TIMEOUT_SECONDS do
		local response = Net.request(if observedId
				then `{api}/repos/{repository}/actions/runs/{observedId}`
				else `{api}/repos/{repository}/actions/runs?branch={encoded}&event=push&per_page=30`, {
			headers = {
				Authorization = `Bearer {token}`,
				Accept = "application/vnd.github+json",
				["User-Agent"] = "Luau-CI-bootstrap",
			},
		})
		if not response.ok then
			error(`Cannot inspect native PR execution (HTTP {response.status}); gate needs Actions: read`, 0)
		end
		local decoded: unknown = Json.decode(response.body)
		local runs: { unknown }

		if observedId then
			if type(decoded) ~= "table" or type(decoded.id) ~= "number" or decoded.id ~= observedId then
				error("GitHub returned an invalid native PR execution run", 0)
			end
			runs = { decoded }
		else
			if type(decoded) ~= "table" or type(decoded.workflow_runs) ~= "table" then
				error("GitHub returned an invalid workflow run list", 0)
			end
			runs = decoded.workflow_runs :: { unknown }
		end

		for _, item in runs do
			if type(item) ~= "table" then
				continue
			end

			if not observedId then
				local path = item.path
				if type(path) ~= "string" or not path:find(".github/workflows/ci-execution.yml", 1, true) then
					continue
				end
				if type(item.head_branch) ~= "string" or item.head_branch ~= branch then
					continue
				end
				if type(item.id) ~= "number" then
					continue
				end
				observedId = item.id
				print(`::notice::PR gate is waiting for native CI Execution run {tostring(item.id)}`)
			end

			if item.status == "completed" then
				if item.conclusion == "success" then
					print(`::notice::Native PR execution passed: {tostring(item.html_url)}`)
					return
				end
				error(`Native PR execution concluded {tostring(item.conclusion)}: {tostring(item.html_url)}`, 0)
			end
			break
		end

		if not observedId and os.time() - started >= PR_EXECUTION_START_TIMEOUT_SECONDS then
			error("GitHub did not schedule CI Execution for the generated PR branch within two minutes", 0)
		end
		Task.wait(PR_EXECUTION_POLL_SECONDS)
	end

	-- Distinguish a run that never started from one that outlasted the gate.
	error(
		if observedId
			then "Native PR execution did not finish within the gate timeout"
			else "GitHub did not schedule CI Execution for the generated PR branch",
		0
	)
end

--[[
	Prepares local act artifacts or launches native CI on a generated branch. Pull request plans may contain only read-boundary tasks.

	@return boolean Whether this function handled execution instead of leaving it to the caller.
]]
function BranchRun.TryLaunch(tasks: { Contract.Task }, event: string, credentials: Credentials.Credentials): boolean
	-- Local act generates the workflow for a separate invocation instead of publishing a branch.
	if Process.env.ACT == "true" and Process.env.CI_GRAPH_RUN ~= "true" then
		local head = git({ "rev-parse", "HEAD" })
		if #head ~= 40 or not head:match("^%x+$") then
			error("Local CI execution requires a checked-out commit", 0)
		end
		local branch = `{Configuration.new().branchPrefix}1-1`
		local workflow = Workflow.Render(tasks, head, branch, event)
		-- act binds one shared workspace for every job and every invocation.
		Responses.ResetLocal()
		local directory = "build/run/ci-start/artifacts"
		Fs.createDirectory(directory, { makeParents = true })
		Fs.writeStringToFile(`{directory}/workflow.yml`, workflow)
		Fs.writeStringToFile(`{directory}/event.json`, Json.encode({ ref = `refs/heads/{branch}` }))
		Responses.Write("start", {
			color = "success",
			result = "Local CI Execution workflow generated. Run it with the local Actions task.",
			selected_count = tostring(#tasks),
			source_sha = head,
		})
		print(`::notice::Generated local CI Execution workflow at {directory}/workflow.yml`)
		return true
	end

	-- Only the initial GitHub Actions run should publish a native execution branch.
	if
		Process.env.GITHUB_ACTIONS ~= "true"
		or Process.env.CI_GRAPH_RUN == "true"
		or (event ~= "push" and event ~= "pull_request" and event ~= "workflow_dispatch")
	then
		return false
	end

	-- Reject privileged tasks before requesting credentials or generating a PR execution branch.
	if event == "pull_request" then
		for _, task in tasks do
			if task.boundary ~= "read" then
				error(`PR native execution cannot include privileged component {task.identity}`, 0)
			end
		end
	end

	local configuration = Configuration.new()
	credentials:Describe(configuration)
	if not configuration.enabled then
		print("::notice::github.bootstrap.enabled is false; using the Luau scheduler")
		return false
	end
	local repository = configuration:ResolveRepository(configuration.repository)
	local currentRepository = Process.env.GITHUB_REPOSITORY

	if not currentRepository or repository:lower() ~= currentRepository:lower() then
		print(
			"::warning::github.repository must identify the repository running this bootstrap. Cross-repository publishing aliases do not redirect CI execution. Using the Luau scheduler."
		)
		return false
	end

	local sha = Process.env.GITHUB_SHA
	local runId = Process.env.GITHUB_RUN_ID
	local attempt = Process.env.GITHUB_RUN_ATTEMPT or "1"

	if
		not sha
		or #sha ~= 40
		or not sha:match("^%x+$")
		or not runId
		or not runId:match("^%d+$")
		or not attempt:match("^%d+$")
	then
		error("GitHub bootstrap context has an invalid commit or run identity", 0)
	end

	local roles = { "bootstrap_token" }

	for _, task in tasks do
		for _, role in task.credentials do
			table.insert(roles, role)
		end
	end

	local access = Authentication.Acquire(configuration, credentials, repository, roles)
	if not access then
		return false
	end
	local branch = `{configuration.branchPrefix}{runId}-{attempt}`
	local ok, failure = xpcall(function(): boolean
		launch(tasks, event, repository, branch, sha, access)
		return true
	end, tostring)
	Authentication.Release(access)

	if not ok then
		if access.inspection then
			TokenPermissions.Warn(configuration, "bootstrap_token", access.inspection, true)
		end
		error(`Native CI Execution could not be started: {failure}`, 0)
	end

	if event == "pull_request" then
		waitForPullRequestExecution(repository, branch)
	end
	local server = Process.env.GITHUB_SERVER_URL or "https://github.com"
	local query = branch:gsub("([^%w_.~-])", function(character: string): string
		return string.format("%%%02X", string.byte(character))
	end)
	local url = `{server}/{repository}/actions?query=branch%3A{query}`
	print(`::notice::Started CI execution on {branch}: {url}`)
	Responses.Write("start", {
		color = "success",
		result = if event == "pull_request"
			then "PR gate passed after native CI Execution completed."
			else "Bootstrap completed. CI Execution was started.",
		selected_count = tostring(#tasks),
		execution_url = url,
		source_sha = sha,
	})
	Fs.createDirectory("build/run/ci-start/responses", { makeParents = true })
	Fs.writeStringToFile(
		"build/run/ci-start/responses/launch.json",
		Json.encode({ branch = branch, source = sha, url = url })
	)
	return true
end

--[[
	Deletes the generated branch only while it still points at this run's original commit. The ordinary job token can delete the ref without the App's workflow-write access.
]]
function BranchRun.Cleanup(): ()
	if Process.env.ACT == "true" then
		print("Local act execution: no remote CI branch was created")
		return
	end
	local token = Process.env.GH_TOKEN
	Process.env.GH_TOKEN = nil
	local branch = Process.env.CI_RUN_BRANCH
	local ref = Process.env.GITHUB_REF
	local eventSha = Process.env.GITHUB_SHA
	local repository = Process.env.GITHUB_REPOSITORY
	if Process.env.GITHUB_ACTIONS ~= "true" or Process.env.CI_GRAPH_RUN ~= "true" then
		error("Branch cleanup is only available inside a generated CI run", 0)
	end
	if not token or token == "" or not branch or not repository or not eventSha then
		error("Branch cleanup is missing its GitHub context or automatic token", 0)
	end
	local configuration = Configuration.new()
	local suffix = branch:sub(#configuration.branchPrefix + 1)
	if branch:sub(1, #configuration.branchPrefix) ~= configuration.branchPrefix or not suffix:match("^%d+%-%d+$") then
		error("Refusing to delete a branch outside the configured CI run namespace", 0)
	end
	if ref ~= `refs/heads/{branch}` or #eventSha ~= 40 or not eventSha:match("^%x+$") then
		error("Refusing cleanup outside this workflow's original branch and commit context", 0)
	end
	if configuration:ResolveRepository(configuration.repository):lower() ~= repository:lower() then
		error("Refusing to delete a branch in another repository", 0)
	end
	local api = Process.env.GITHUB_API_URL or "https://api.github.com"
	local headers = {
		Authorization = "Bearer " .. token,
		Accept = "application/vnd.github+json",
		["User-Agent"] = "Luau-CI-bootstrap",
	}
	local repositoryResponse = Net.request(`{api}/repos/{repository}`, { headers = headers })
	if not repositoryResponse.ok then
		error(`Unable to check repository default branch: HTTP {repositoryResponse.status}`, 0)
	end
	local metadata: unknown = Json.decode(repositoryResponse.body)
	if type(metadata) ~= "table" or type(metadata.default_branch) ~= "string" then
		error("GitHub returned an invalid repository default branch", 0)
	end
	if branch == metadata.default_branch then
		error("Refusing to delete the default branch", 0)
	end
	local encoded = branch:gsub("([^%w_.~-])", function(character: string): string
		return string.format("%%%02X", string.byte(character))
	end)
	local current = Net.request(`{api}/repos/{repository}/git/ref/heads/{encoded}`, { headers = headers })
	if current.status == 404 then
		print("::notice::Temporary CI branch was already removed")
		return
	end
	if not current.ok then
		error(`Unable to inspect temporary CI branch: HTTP {current.status}`, 0)
	end
	local decoded: unknown = Json.decode(current.body)
	if type(decoded) ~= "table" or type(decoded.object) ~= "table" then
		error("GitHub returned an invalid branch reference", 0)
	end
	local target: unknown = decoded.object
	if type(target) ~= "table" or type(target.sha) ~= "string" or target.sha ~= eventSha then
		error("Temporary CI branch moved after this run started; leaving it untouched", 0)
	end
	local removed =
		Net.request(`{api}/repos/{repository}/git/refs/heads/{encoded}`, { method = "DELETE", headers = headers })
	if not removed.ok and removed.status ~= 404 then
		error(`Unable to remove temporary CI branch: HTTP {removed.status}`, 0)
	end
	print(`::notice::Removed temporary CI branch {branch}`)
end

return BranchRun
