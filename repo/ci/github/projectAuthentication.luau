-- repo/ci/github/projectAuthentication.luau
--!strict

local Process = require("@lune/process")
local Fs = require("@lune/fs")
local Configuration = require("./configuration")
local Authentication = require("./authentication")
local Publication = require("./publication")

local ProjectAuthentication = {}
export type Supplied = { appId: string?, privateKey: string?, token: string? }

function ProjectAuthentication.Warn(owner: string): ()
	local configuration = Configuration.new()
	local values: { [string]: string } = {
		owner = owner,
		app_id = configuration.credentials.app_id or "<github.credentials.app_id>",
		app_private_key = configuration.credentials.app_private_key or "<github.credentials.app_private_key>",
		projects_token = configuration.credentials.projects_token or "<github.credentials.projects_token>",
	}
	local text = Fs.readFile("repo/content/ci/projects-authorization.md"):gsub("{{([%w_]+)}}", function(key)
		return values[key] or key
	end)
	local path = Process.env.GITHUB_STEP_SUMMARY
	if path then
		local current = if Fs.isFile(path) then Fs.readFile(path) else ""
		Fs.writeFile(path, current .. "\n" .. text)
	end
end
function ProjectAuthentication.Read(): Supplied
	local supplied: Supplied = {
		appId = Process.env.CI_CREDENTIAL_APP_ID,
		privateKey = Process.env.CI_CREDENTIAL_APP_PRIVATE_KEY,
		token = Process.env.CI_CREDENTIAL_PROJECTS_TOKEN,
	}
	Process.env.CI_CREDENTIAL_APP_ID = nil
	Process.env.CI_CREDENTIAL_APP_PRIVATE_KEY = nil
	Process.env.CI_CREDENTIAL_PROJECTS_TOKEN = nil
	return supplied
end

function ProjectAuthentication.Acquire(supplied: Supplied, repository: string, owner: string): Authentication.Access?
	local configuration = Configuration.new()
	local idName = configuration.credentials.app_id or "<github.credentials.app_id>"
	local keyName = configuration.credentials.app_private_key or "<github.credentials.app_private_key>"
	local tokenName = configuration.credentials.projects_token or "<github.credentials.projects_token>"
	if supplied.appId and supplied.appId ~= "" and supplied.privateKey and supplied.privateKey ~= "" then
		local status, account = Publication.Request("GET", `users/{Publication.Encode(owner)}`)
		Publication.RequireSuccess(status, `Read project owner {owner}`)
		if account.type == "Organization" then
			local ok, access = pcall(
				Authentication.AppAccess,
				supplied.appId,
				supplied.privateKey,
				repository,
				{ organization_projects = "write" },
				owner
			)
			if ok then
				print(`Using configured App {idName}/{keyName} for Projects owned by {owner}`)
				return access
			end
			print(
				`::warning::App {idName}/{keyName} could not obtain Organization Projects write access for {owner}; checking {tokenName}`
			)
		else
			print(
				`::warning::User-owned Projects need user authorization; checking configured token secret {tokenName}`
			)
		end
	end
	local token = supplied.token
	if token and token ~= "" and tokenName:upper() ~= "GITHUB_TOKEN" and token ~= Process.env.GH_TOKEN then
		print(`Using configured Projects credential secret {tokenName} for {owner}`)
		return { token = token, temporary = false }
	end
	print(
		`::warning::Projects sync skipped for {owner}: configure secret {tokenName} with a Projects-capable user token, or for an organization configure App {idName}/{keyName}. See the run summary for personal and organization setup instructions. Store credential values in GitHub Secrets.`
	)
	ProjectAuthentication.Warn(owner)
	return nil
end

return ProjectAuthentication
