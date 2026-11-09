-- ci/github/authentication/projectAuthentication.luau
--!strict

local Process = require("@lute/process")
local Configuration = require("@ci/github/configuration")
local Authentication = require("@ci/github/authentication/authentication")
local Publication = require("@ci/github/publication")
local TokenPermissions = require("@ci/github/authentication/tokenPermissions")
local SetupInstructions = require("@ci/github/authentication/setupInstructions")
local Responses = require("@ci/github/reporting/responses")

local ProjectAuthentication = {}
export type Supplied = { appId: string?, privateKey: string?, token: string?, verified: boolean }

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
	local permissions = configuration.roles.projects_token.permissions.organization
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
	local tokenName = configuration.credentials.projects_token or "<credentials.json roles.projects_token>"
	local values = SetupInstructions.Values(configuration, tokenName, scopes, {}, permissions, owner)
	values.app_permissions = table.concat(appPermissions, "\n")
	values.classic_scopes = table.concat(classicScopes, "\n")
	values.projects_token = tokenName
	values.permission_evidence = TokenPermissions.Evidence(
		inspection,
		reason == "insufficient" and (not inspection or inspection.state == "verified")
	)
	SetupInstructions.Guides(values, true)
	values.organization_setup = if values.owner_type == "User"
		then ""
		else SetupInstructions.Render("projects.organization-setup", values)
	local outcome = reason or "missing"
	print(
		`::warning::Projects authorization for {owner}: {outcome}. Configure/update {tokenName} or the configured App; see the job summary.`
	)
	local template = Responses.Template("projects." .. outcome) .. "\n\n" .. Responses.Template("projects.setup")
	local text = template:gsub("{{([%w_]+)}}", function(key)
		return values[key] or error(`Unknown Projects authorization template field {key}`, 0)
	end)
	Responses.Record("authorization/projects/" .. owner, text)
end

function ProjectAuthentication.Read(): Supplied
	local supplied: Supplied = {
		appId = Process.env.CI_CREDENTIAL_APP_ID,
		privateKey = Process.env.CI_CREDENTIAL_APP_PRIVATE_KEY,
		token = Process.env.CI_CREDENTIAL_PROJECTS_TOKEN,
		verified = Process.env.CI_CREDENTIAL_PROJECTS_TOKEN_VERIFIED == "true",
	}
	Process.env.CI_CREDENTIAL_APP_ID = nil
	Process.env.CI_CREDENTIAL_APP_PRIVATE_KEY = nil
	Process.env.CI_CREDENTIAL_PROJECTS_TOKEN = nil
	Process.env.CI_CREDENTIAL_PROJECTS_TOKEN_VERIFIED = nil
	return supplied
end

function ProjectAuthentication.Acquire(supplied: Supplied, repository: string, owner: string): Authentication.Access?
	local configuration = Configuration.new()
	local idName = configuration.credentials.app_id or "<credentials.json roles.app_id>"
	local keyName = configuration.credentials.app_private_key or "<credentials.json roles.app_private_key>"
	local tokenName = configuration.credentials.projects_token or "<credentials.json roles.projects_token>"

	if supplied.appId and supplied.appId ~= "" and supplied.privateKey and supplied.privateKey ~= "" then
		local permissions = configuration.roles.projects_token.permissions.organization
		local status, account = Publication.Request("GET", `users/{Publication.Encode(owner)}`)
		Publication.RequireSuccess(status, `Read project owner {owner}`, account)
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
			print(`::notice::User-owned Projects use user authorization; checking configured token secret {tokenName}`)
		end
	end

	local token = supplied.token

	if token and token ~= "" and tokenName:upper() ~= "GITHUB_TOKEN" and token ~= Process.env.GH_TOKEN then
		local scopes = combinedScopes(configuration)
		local inspection: TokenPermissions.Inspection = if supplied.verified
			then { state = "verified", required = scopes, missing = {} }
			else TokenPermissions.Inspect(token, scopes)
		if inspection.state == "insufficient" or inspection.state == "invalid" then
			ProjectAuthentication.Warn(owner, "insufficient", inspection)
			return nil
		end

		if inspection.state == "unverified" then
			print(
				`::warning::Credential {tokenName}: GitHub did not expose a verifiable scope inventory. Projects API access is still checked during synchronization.`
			)
		end

		print(`Using selected Projects credential for {owner}`)
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
