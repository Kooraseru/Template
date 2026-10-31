-- repo/ci/github/projectAuthentication.luau
--!strict

local Process = require("@lune/process")
local Fs = require("@lune/fs")
local Serde = require("@lune/serde")
local Configuration = require("./configuration")
local Authentication = require("./authentication")
local Publication = require("./publication")
local TokenPermissions = require("./tokenPermissions")

local ProjectAuthentication = {}
export type Supplied = { appId: string?, privateKey: string?, token: string? }

local function requirements(): { [string]: string }
	local root = Publication.Record(Serde.decode("toml", Fs.readFile("repo/config/ci/authorization/projects.toml")))
	local app = Publication.Record(Publication.Record(root.app).organization)
	local permissions: { [string]: string } = {}
	for name, value in app do
		if not name:match("^[a-z_]+$") or (value ~= "read" and value ~= "write") then
			error("Invalid Projects App permission declaration", 0)
		end
		permissions[name] = value
	end
	if next(permissions) == nil then
		error("Projects App permissions must not be empty", 0)
	end
	return permissions
end

local function combinedScopes(configuration: Configuration.Configuration): { string }
	return TokenPermissions.Required(
		configuration,
		if configuration.enabled then { "projects_token", "bootstrap_token" } else { "projects_token" },
		"projects_token"
	)
end

function ProjectAuthentication.Warn(
	owner: string,
	reason: ("missing" | "insufficient")?,
	inspection: TokenPermissions.Inspection?
): ()
	local configuration = Configuration.new()
	local permissions = requirements()
	local scopes = combinedScopes(configuration)
	local appPermissions: { string } = {}
	for name, value in permissions do
		table.insert(appPermissions, `- \`{name}\`: {value}`)
	end
	table.sort(appPermissions)
	local classicScopes: { string } = {}
	for _, scope in scopes do
		table.insert(classicScopes, `- \`{scope}\``)
	end
	local repository = configuration:ResolveRepository(configuration.repository)
	local tokenName = configuration.credentials.projects_token or "<github.credentials.projects_token>"
	local description = Publication.Encode(`{tokenName} - CI for {repository}`)
	local requestedScopes = Publication.Encode(table.concat(scopes, ","))
	local tokenUrl = `https://github.com/settings/tokens/new?description={description}&scopes={requestedScopes}`
	local values: { [string]: string } = {
		owner = owner,
		repository = repository,
		classic_token_url = tokenUrl,
		app_permissions = table.concat(appPermissions, "\n"),
		classic_scopes = table.concat(classicScopes, "\n"),
		app_id = configuration.credentials.app_id or "<github.credentials.app_id>",
		app_private_key = configuration.credentials.app_private_key or "<github.credentials.app_private_key>",
		projects_token = tokenName,
		permission_evidence = TokenPermissions.Evidence(
			inspection,
			reason == "insufficient" and (not inspection or inspection.state == "verified")
		),
	}
	local outcome = reason or "missing"
	print(
		`::warning::Projects authorization for {owner}: {outcome}. Configure/update {tokenName} or the configured App; see the job summary.`
	)
	local folder = "repo/content/ci/projects-authorization"
	local template = Fs.readFile(`{folder}/{outcome}.md`) .. "\n\n" .. Fs.readFile(`{folder}/setup.md`)
	local text = template:gsub("{{([%w_]+)}}", function(key)
		return values[key] or error(`Unknown Projects authorization template field {key}`, 0)
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
		local permissions = requirements()
		local status, account = Publication.Request("GET", `users/{Publication.Encode(owner)}`)
		Publication.RequireSuccess(status, `Read project owner {owner}`)
		if account.type == "Organization" then
			local ok, access =
				pcall(Authentication.AppAccess, supplied.appId, supplied.privateKey, repository, permissions, owner)
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
		local inspection = TokenPermissions.Inspect(token, combinedScopes(configuration))
		if inspection.state == "insufficient" or inspection.state == "invalid" then
			ProjectAuthentication.Warn(owner, "insufficient", inspection)
			return nil
		end
		if inspection.state == "unverified" then
			print(
				`::warning::Credential {tokenName}: GitHub did not expose a verifiable scope inventory. Projects API access is still checked during synchronization.`
			)
		end
		print(`Using configured Projects credential secret {tokenName} for {owner}`)
		return { token = token, temporary = false, inspection = inspection }
	end
	print(
		`::warning::Projects sync skipped for {owner}: configure secret {tokenName} with a Projects-capable user token, or for an organization configure App {idName}/{keyName}. See the run summary for personal and organization setup instructions. Store credential values in GitHub Secrets.`
	)
	local suppliedCredential = (supplied.appId and supplied.appId ~= "") or (token and token ~= "")
	ProjectAuthentication.Warn(owner, if suppliedCredential then "insufficient" else "missing")
	return nil
end

return ProjectAuthentication
