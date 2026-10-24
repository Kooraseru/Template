-- ci/utilities/github.luau
--!strict

local GitHub = {}

--# Modules

local Process = require("@lune/process")
local Serde = require("@lune/serde")
local Rules = require("../validation/rules")
local Commands = require("./commands")

--# Functions

function GitHub.Repository(): string
	local configured = Process.env.GITHUB_REPOSITORY or Process.env.GH_REPO

	if configured and configured ~= "" then
		return configured
	end

	local result = Process.exec("gh", { "repo", "view", "--json", "nameWithOwner", "--jq", ".nameWithOwner" })
	assert(result.ok, "cannot identify repository: " .. result.stderr)

	return (result.stdout:gsub("%s+$", ""))
end

function GitHub.Api(endpoint: string, method: string?, body: unknown): unknown
	local arguments = { "api", endpoint, "--method", method or "GET" }
	local input: string? = nil

	if body ~= nil then
		table.insert(arguments, "--input")
		table.insert(arguments, "-")
		input = Serde.encode("json", body)
	end

	local result = Commands.Run("gh", arguments, input)

	if result:match("^%s*$") then
		return nil
	end

	return Serde.decode("json", result)
end

function GitHub.IsAdmin(login: string?): boolean
	if not login or not login:match("^[%w%-]+$") then
		return false
	end

	local permissions =
		Rules.Entries(GitHub.Api("repos/" .. GitHub.Repository() .. "/collaborators/" .. login .. "/permission"))

	return permissions.permission == "admin"
end

function GitHub.Actor(): string
	if Process.env.GITHUB_ACTOR then
		return Process.env.GITHUB_ACTOR
	end

	local user = Rules.Entries(GitHub.Api("user"))
	assert(type(user.login) == "string", "missing authenticated login")

	return user.login
end

return GitHub
