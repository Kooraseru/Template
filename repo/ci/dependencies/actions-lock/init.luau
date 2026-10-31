-- repo/ci/dependencies/actions-lock/init.luau
--!strict

local Fs = require("@lune/fs")
local Process = require("@lune/process")
local Serde = require("@lune/serde")
local Publication = require("@ci/github/publication")

local ActionsLock = {}

function ActionsLock.Lock(directory: string, workflow: string): ()
	local root = Publication.Record(Serde.decode("toml", Fs.readFile("repo/config/ci/dependencies/actions-lock.toml")))
	local tool = Publication.Record(root.tool)
	local repository = Publication.Text(tool.repository)
	local version = Publication.Text(tool.version)
	if repository ~= "github/gh-actions-lock" or not version:match("^v%d+%.%d+%.%d+$") then
		error("Invalid official actions-lock tool pin", 0)
	end
	local checked = Process.exec("gh", { "actions-lock", "--version" })
	if not checked.ok then
		local installed = Process.exec("gh", { "extension", "install", repository, "--pin", version })
		if not installed.ok then
			error(`Install {repository} at {version} to lock generated workflows`, 0)
		end
		checked = Process.exec("gh", { "actions-lock", "--version" })
	end
	if not checked.ok or checked.stdout:gsub("%s+$", "") ~= "actions-lock version " .. version then
		error(`actions-lock must match pinned version {version}`, 0)
	end
	local result = Process.exec(
		"gh",
		{ "actions-lock", "--no-interactive", "--no-narrow", workflow },
		{ cwd = directory }
	)
	if not result.ok then
		error("Official GitHub Actions lockfile generation failed; no execution branch will be pushed", 0)
	end
	local verified = Process.exec("gh", { "actions-lock", "--verify-local", workflow }, { cwd = directory })
	if not verified.ok then
		error("Generated workflow is not covered by actions.lock", 0)
	end
end

return ActionsLock
