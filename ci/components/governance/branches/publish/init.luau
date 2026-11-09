-- ci/components/governance/branches/publish/init.luau
--!strict

local Fs = require("@std/fs")
local Process = require("@lute/process")
local Publication = require("@ci/github/publication")
local GitFailure = require("@ci/github/publication/gitFailure")
local Glob = require("@ci/bootstrap/discovery/glob")

local Component = {}
Component.__index = Component
export type Component = setmetatable<{}, typeof(Component)>

local function git(arguments: { string }, directory: string, operation: string?, ref: string?): string
	local environment = table.clone(Process.env)
	environment.GIT_TERMINAL_PROMPT = "0"
	environment.CI_GIT_BOOTSTRAP_TOKEN = environment.GH_TOKEN
	local result = Process.run({ "git", table.unpack(arguments) }, {
		cwd = directory,
		env = environment,
	})
	if not result.ok then
		error(`Branch publication Git {operation or arguments[1]} {ref or ""} failed with exit code {result.exitcode}: {GitFailure(result.stderr)}`, 0)
	end
	return (result.stdout:gsub("%s+$", ""))
end

function Component.new(): Component
	return setmetatable({}, Component)
end

function Component.Run(self: Component, _: { event: string }): string?
	local repository = Publication.Begin("BRANCHES")
	if not repository then
		return "skipped"
	end
	Process.env.CI_GIT_CREDENTIAL_HELPER =
		`{Process.cwd()}/ci/github/authentication/git-credential.sh`
	local status, details = Publication.Request("GET", `repos/{repository}`)
	Publication.RequireSuccess(status, "Read default branch", details)
	local remote = if Process.env.TEMPLATE_PUBLICATION_REHEARSAL == "1"
		then "/tmp/template-preflight.git" else `https://github.com/{repository}.git`
	for _, directory in Glob.Find("build/github/branches/*") do
		if not (Fs.exists(directory) and Fs.type(directory) == "dir") then
			error("Expected a generated branch directory", 0)
		end
		local branch = directory:match("([^/]+)$")
		if not branch or not branch:match("^[%w][%w_-]*$") or branch == details.default_branch then
			error("Refusing to publish an unsafe branch or replace the default source branch", 0)
		end
		if Fs.exists(`{directory}/.git`) then
			error("Refusing to reuse a branch publication Git directory", 0)
		end
		git({ "init", "--quiet" }, directory)
		git({ "remote", "add", "origin", remote }, directory)
		local credential = { "-c", "credential.helper=", "-c", 'credential.helper=!bash "$CI_GIT_CREDENTIAL_HELPER"' }
		local lookup = git({
			credential[1],
			credential[2],
			credential[3],
			credential[4],
			"ls-remote",
			remote,
			`refs/heads/{branch}`,
		}, directory, "ls-remote", `refs/heads/{branch}`)
		local parent: string? = nil

		if lookup ~= "" then
			git({
				credential[1],
				credential[2],
				credential[3],
				credential[4],
				"fetch",
				"--quiet",
				"origin",
				`refs/heads/{branch}`,
			}, directory)
			parent = git({ "rev-parse", "FETCH_HEAD" }, directory)
		end

		git({ "add", "--all" }, directory)
		local tree = git({ "write-tree" }, directory)
		if parent and tree == git({ "rev-parse", parent .. "^{tree}" }, directory) then
			print(`Branch {branch} is already current`)
			continue
		end
		local arguments = {
			"-c",
			"user.name=github-actions[bot]",
			"-c",
			"user.email=41898282+github-actions[bot]@users.noreply.github.com",
			"commit-tree",
			tree,
		}
		if parent then
			table.insert(arguments, "-p")
			table.insert(arguments, parent)
		end
		table.insert(arguments, "-m")
		table.insert(arguments, "Publish generated repository output")
		local commit = git(arguments, directory)
		git({
			credential[1],
			credential[2],
			credential[3],
			credential[4],
			"push",
			"origin",
			`{commit}:refs/heads/{branch}`,
		}, directory, "push", `refs/heads/{branch}`)
		print(`Published branch https://github.com/{repository}/tree/{branch}`)
	end
	return nil
end

return Component
