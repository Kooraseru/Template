-- repo/ci/components/publish-branches/init.luau
--!strict

local Fs = require("@lune/fs")
local Process = require("@lune/process")
local Publication = require("@ci/github/publication")
local Glob = require("@ci/bootstrap/glob")

local Component = {}
Component.__index = Component
export type Component = setmetatable<{}, typeof(Component)>

local function git(arguments: { string }, directory: string, input: string?): string
	local result = Process.exec("git", arguments, {
		cwd = directory,
		stdio = { stdin = input },
		env = { GIT_TERMINAL_PROMPT = "0" },
	})
	if not result.ok then
		error("Branch publication Git operation failed; check contents permission and branch protections", 0)
	end
	return (result.stdout:gsub("%s+$", ""))
end

function Component.new(): Component
	return setmetatable({}, Component)
end

function Component.Run(_self: Component, _context: { event: string }): string?
	local repository = Publication.Begin("BRANCHES")
	if not repository then
		return "skipped"
	end
	local status, details = Publication.Request("GET", `repos/{repository}`)
	Publication.RequireSuccess(status, "Read default branch")
	for _, directory in Glob.Find("build/repo/branches/*") do
		if not Fs.isDir(directory) then
			error("Expected a generated branch directory", 0)
		end
		local branch = directory:match("([^/]+)$")
		if not branch or not branch:match("^[%w][%w_-]*$") or branch == details.default_branch then
			error("Refusing to publish an unsafe branch or replace the default source branch", 0)
		end
		if Fs.metadata(`{directory}/.git`).exists then
			error("Refusing to reuse a branch publication Git directory", 0)
		end
		git({ "init", "--quiet" }, directory)
		git({ "remote", "add", "origin", `https://github.com/{repository}.git` }, directory)
		local credential = { "-c", "credential.helper=", "-c", "credential.helper=!gh auth git-credential" }
		local lookup = Process.exec("git", {
			credential[1],
			credential[2],
			credential[3],
			credential[4],
			"ls-remote",
			`https://github.com/{repository}.git`,
			`refs/heads/{branch}`,
		})
		if not lookup.ok then
			error("Unable to inspect destination branch", 0)
		end
		local parent: string? = nil
		if lookup.stdout ~= "" then
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
		local commit = git(arguments, directory, "Publish generated repository output\n")
		git({
			credential[1],
			credential[2],
			credential[3],
			credential[4],
			"push",
			"origin",
			`{commit}:refs/heads/{branch}`,
		}, directory)
		print(`Published branch https://github.com/{repository}/tree/{branch}`)
	end
	return nil
end

return Component
