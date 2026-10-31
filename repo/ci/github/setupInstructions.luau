-- repo/ci/github/setupInstructions.luau
--!strict

local Fs = require("@lune/fs")
local Process = require("@lune/process")
local Serde = require("@lune/serde")
local Configuration = require("./configuration")
local Publication = require("./publication")

local SetupInstructions = {}

local function ownerType(owner: string): string
	local path = Process.env.GITHUB_EVENT_PATH
	if not path or not Fs.isFile(path) then
		return "Unknown"
	end
	local ok, event = pcall(function(): unknown
		return Serde.decode("json", Fs.readFile(path))
	end)
	if
		ok
		and type(event) == "table"
		and type(event.repository) == "table"
		and type(event.repository.owner) == "table"
	then
		local account = Publication.Record(event.repository.owner)
		if type(account.login) == "string" and account.login:lower() == owner:lower() then
			if account.type == "User" or account.type == "Organization" then
				return account.type
			end
		end
	end
	return "Unknown"
end

function SetupInstructions.Render(path: string, values: { [string]: string }): string
	local text = Fs.readFile(path):gsub("{{([%w_]+)}}", function(key)
		return values[key] or error(`{path}: unknown instruction field {key}`, 0)
	end)
	return text
end

local function permissionQuery(permissions: { [string]: string }): string
	local names: { string } = {}
	for name, access in permissions do
		if not name:match("^[a-z_]+$") or (access ~= "read" and access ~= "write") then
			error("Invalid App registration permission", 0)
		end
		table.insert(names, name)
	end
	table.sort(names)
	local query = ""
	for _, name in names do
		query ..= "&" .. Publication.Encode(name) .. "=" .. permissions[name]
	end
	return query
end

function SetupInstructions.Values(
	configuration: Configuration.Configuration,
	credential: string,
	scopes: { string },
	repositoryPermissions: { [string]: string }?,
	organizationPermissions: { [string]: string }?,
	projectOwner: string?
): { [string]: string }
	local repository = configuration:ResolveRepository(configuration.repository)
	local owner = projectOwner or repository:match("^([^/]+)/")
	if not owner then
		error("Repository owner is required for setup links", 0)
	end
	local base = "https://github.com/" .. repository
	local repoPermissions = table.clone(repositoryPermissions or {})
	local function mergeRepository(path: string): ()
		local root = Publication.Record(Serde.decode("toml", Fs.readFile(path)))
		for name, access in Publication.Record(Publication.Record(root.app).repository) do
			if repoPermissions[name] ~= "write" then
				repoPermissions[name] = Publication.Text(access)
			end
		end
	end
	if configuration.enabled then
		mergeRepository("repo/config/ci/authorization/bootstrap.toml")
	end
	local execution = Publication.Record(Serde.decode("toml", Fs.readFile("repo/config/ci/execution.toml")))
	local skip = Publication.Record(execution.skip)
	local neutral = skip.default == "neutral"
	for _, conclusion in Publication.Record(skip.components) do
		neutral = neutral or conclusion == "neutral"
	end
	if neutral then
		mergeRepository("repo/config/ci/authorization/check-runs.toml")
	end
	local appQuery = "?name="
		.. Publication.Encode(repository:gsub("/", "-") .. "-CI")
		.. "&description="
		.. Publication.Encode("CI automation for " .. repository)
		.. "&url="
		.. Publication.Encode(base)
		.. "&public=false&webhook_active=false"
		.. permissionQuery(repoPermissions)
	local run = Process.env.GITHUB_RUN_ID
	local retry = if run and run:match("^%d+$")
		then `gh run rerun {run} --repo {repository}`
		else `gh run list --repo {repository} --limit 5`
	local permissionRows: { string } = {}
	for name, access in repoPermissions do
		table.insert(permissionRows, `- Repository: {name} = {access}`)
	end
	for name, access in organizationPermissions or {} do
		table.insert(permissionRows, `- Organization: {name} = {access}`)
	end
	table.sort(permissionRows)
	return {
		repository = repository,
		owner = owner,
		owner_type = ownerType(owner),
		credential = credential,
		tokens_url = "https://github.com/settings/tokens",
		required_scopes = "`" .. table.concat(scopes, "`, `") .. "`",
		token_url = "https://github.com/settings/tokens/new?description=" .. Publication.Encode(
			credential .. " - CI for " .. repository
		) .. "&scopes=" .. Publication.Encode(table.concat(scopes, ",")),
		personal_app_url = "https://github.com/settings/apps/new" .. appQuery,
		organization_app_url = "https://github.com/organizations/"
			.. Publication.Encode(owner)
			.. "/settings/apps/new"
			.. appQuery
			.. permissionQuery(organizationPermissions or {}),
		apps_url = "https://github.com/settings/apps",
		organization_apps_url = "https://github.com/organizations/" .. Publication.Encode(owner) .. "/settings/apps",
		app_registration_permissions = table.concat(permissionRows, "\n   "),
		secrets_url = base .. "/settings/secrets/actions",
		variables_url = base .. "/settings/variables/actions",
		actions_url = base .. "/actions" .. (if run and run:match("^%d+$") then "/runs/" .. run else ""),
		retry_command = retry,
		execution_config_url = base .. "/blob/HEAD/repo/config/ci/execution.toml",
		app_id = configuration.credentials.app_id or "<github.credentials.app_id>",
		app_private_key = configuration.credentials.app_private_key or "<github.credentials.app_private_key>",
	}
end

function SetupInstructions.Guides(values: { [string]: string }, organizationOnly: boolean?): ()
	local folder = "repo/content/ci/authorization"
	local accountChoices = if organizationOnly or values.owner_type == "Organization"
		then "app-account-organization.md"
		else if values.owner_type == "User" then "app-account-personal.md" else "app-account.md"
	values.app_account_choices = SetupInstructions.Render(`{folder}/{accountChoices}`, values)
	if organizationOnly or values.owner_type == "Organization" then
		values.apps_url = values.organization_apps_url
	end
	values.app_registration = SetupInstructions.Render(`{folder}/app-registration.md`, values)
	values.app_setup = SetupInstructions.Render(`{folder}/app-setup.md`, values)
	values.token_setup = SetupInstructions.Render(`{folder}/token-setup.md`, values)
end

return SetupInstructions
