-- repo/ci/github/branchRun.luau
--!strict

local Fs = require("@lune/fs")
local Net = require("@lune/net")
local Process = require("@lune/process")
local Serde = require("@lune/serde")
local Contract = require("@ci/bootstrap/contract")
local Authentication = require("./authentication")
local Configuration = require("./configuration")
local Credentials = require("./credentials")
local Workflow = require("./workflow")

local BranchRun = {}

local function git(arguments: { string }, cwd: string?, token: string?): string
	local result = Process.exec("git", arguments, {
		cwd = cwd,
		env = if token then { GH_TOKEN = token, GIT_TERMINAL_PROMPT = "0" } else nil,
	})
	if not result.ok then
		-- Credential helpers and server errors are deliberately not echoed.
		error("GitHub branch bootstrap Git operation failed", 0)
	end
	return (result.stdout:gsub("%s+$", ""))
end

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
	local worktree = `build/github/worktree-{runId}-{attempt}`
	if Fs.metadata(worktree).exists then
		error("Refusing to reuse an existing bootstrap worktree", 0)
	end
	local valid = Process.exec("git", { "check-ref-format", `refs/heads/{branch}` })
	if not valid.ok then
		error("github.bootstrap.branch_prefix produced an invalid branch", 0)
	end
	local yaml = Workflow.Render(tasks, sha, branch, event)
	Fs.writeDir("build/github")
	Fs.writeFile("build/github/workflow.yml", yaml)
	git({ "worktree", "add", "--detach", worktree, sha })
	local ok = xpcall(function(): ()
		Fs.writeDir(`{worktree}/.github/workflows`)
		Fs.writeFile(`{worktree}/.github/workflows/ci-execution.yml`, yaml)
		git({ "add", "--", ".github/workflows/ci-execution.yml" }, worktree)
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
		local server = Process.env.GITHUB_SERVER_URL or "https://github.com"
		git({
			"-c",
			"credential.helper=",
			"-c",
			"credential.helper=!gh auth git-credential",
			"push",
			"--porcelain",
			`{server}/{repository}.git`,
			`HEAD:refs/heads/{branch}`,
		}, worktree, access.token)
	end, tostring)
	local removed = Process.exec("git", { "worktree", "remove", "--force", worktree })
	if not removed.ok then
		print("::warning::Could not remove the temporary bootstrap worktree")
	end
	if not ok then
		error(
			"Branch launch failed; verify the configured credential's Contents and Workflows write permissions and repository rules",
			0
		)
	end
end

function BranchRun.TryLaunch(tasks: { Contract.Task }, event: string, credentials: Credentials.Credentials): boolean
	if Process.env.GITHUB_ACTIONS ~= "true" or Process.env.CI_GRAPH_RUN == "true" or event ~= "push" then
		return false
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
	local access = Authentication.Acquire(configuration, credentials, repository)
	if not access then
		return false
	end
	local branch = `{configuration.branchPrefix}{runId}-{attempt}`
	local ok = xpcall(launch, tostring, tasks, event, repository, branch, sha, access)
	Authentication.Release(access)
	if not ok then
		print(
			"::warning::Native job graph could not be launched. Verify the configured App/token and repository branch rules. Continuing with the Luau scheduler."
		)
		return false
	end
	local server = Process.env.GITHUB_SERVER_URL or "https://github.com"
	local query = branch:gsub("([^%w_.~-])", function(character: string): string
		return string.format("%%%02X", string.byte(character))
	end)
	local url = `{server}/{repository}/actions?query=branch%3A{query}`
	print(`::notice::Started CI execution on {branch}: {url}`)
	local summary = Process.env.GITHUB_STEP_SUMMARY
	if summary then
		Fs.writeFile(
			summary,
			`Bootstrap handed the discovered graph to [CI Execution]({url}).\n\nSource commit: {sha}\n`
		)
	end
	Fs.writeFile("build/github/launch.json", Serde.encode("json", { branch = branch, source = sha, url = url }))
	return true
end

-- Cleanup is restricted to this generated run's unchanged branch. Its ordinary
-- job token can delete a ref without needing the App's workflow-write access.
function BranchRun.Cleanup(): ()
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
	local repositoryResponse = Net.request({ url = `{api}/repos/{repository}`, headers = headers })
	if not repositoryResponse.ok then
		error(`Unable to check repository default branch: HTTP {repositoryResponse.statusCode}`, 0)
	end
	local metadata: unknown = Serde.decode("json", repositoryResponse.body)
	if type(metadata) ~= "table" or type(metadata.default_branch) ~= "string" then
		error("GitHub returned an invalid repository default branch", 0)
	end
	if branch == metadata.default_branch then
		error("Refusing to delete the default branch", 0)
	end
	local encoded = branch:gsub("([^%w_.~-])", function(character: string): string
		return string.format("%%%02X", string.byte(character))
	end)
	local current = Net.request({ url = `{api}/repos/{repository}/git/ref/heads/{encoded}`, headers = headers })
	if current.statusCode == 404 then
		print("::notice::Temporary CI branch was already removed")
		return
	end
	if not current.ok then
		error(`Unable to inspect temporary CI branch: HTTP {current.statusCode}`, 0)
	end
	local decoded: unknown = Serde.decode("json", current.body)
	if type(decoded) ~= "table" or type(decoded.object) ~= "table" then
		error("GitHub returned an invalid branch reference", 0)
	end
	local target: unknown = decoded.object
	if type(target) ~= "table" or type(target.sha) ~= "string" or target.sha ~= eventSha then
		error("Temporary CI branch moved after this run started; leaving it untouched", 0)
	end
	local removed =
		Net.request({ url = `{api}/repos/{repository}/git/refs/heads/{encoded}`, method = "DELETE", headers = headers })
	if not removed.ok and removed.statusCode ~= 404 then
		error(`Unable to remove temporary CI branch: HTTP {removed.statusCode}`, 0)
	end
	print(`::notice::Removed temporary CI branch {branch}`)
end

return BranchRun
