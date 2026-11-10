-- ci/github/configuration/init.luau
--!strict

local Process = require("@lute/process")
local Fs = require("@std/fs")
local Json = require("@formats/json")
local Toml = require("@formats/toml")

const CONFIG_PATH = ".github/config/targets.toml"

const CREDENTIAL_PATH = ".github/config/credentials.json"

export type Permissions = {
	classic: { string },
	repository: { [string]: string },
	organization: { [string]: string },
}
export type Role = { name: string, sources: { string }, permissions: Permissions, selection: string, fallbackName: string? }
export type Oidc = { endpoint: string, audience: string }
export type Profile = {
	bootstrap: { string },
	delegate: boolean,
	credentialProvider: ("github-context" | "oidc" | "environment")?,
	oidc: Oidc?,
	githubContext: boolean,
	contextKeys: { string },
	usesCommands: boolean,
	bootstrapEnvironment: string?,
	reportingEnvironment: string?,
}

local Configuration = {}
Configuration.__index = Configuration

type Fields = {
	repository: string,
	aliases: { [string]: string },
	enabled: boolean,
	branchPrefix: string,
	credentials: { [string]: string },
	roles: { [string]: Role },
	profiles: { [string]: Profile },
	neutralCheck: { [string]: string },
	environments: { [string]: { [string]: string } },
	publication: { [string]: boolean },
}

export type Configuration = setmetatable<Fields, typeof(Configuration)>

local function invalid(message: string): never
	error(`{CONFIG_PATH}: {message}`, 0)
end

local function text(value: unknown, label: string): string
	if type(value) ~= "string" or value == "" or value:find("[%c%s]") then
		return invalid(`{label} must be a nonempty string without whitespace`)
	end
	return value
end

local function record(value: unknown, label: string): { [string]: unknown }
	if type(value) ~= "table" then
		return invalid(`{label} must be a table`)
	end
	local result: { [string]: unknown } = {}
	for key, item in value do
		if type(key) ~= "string" then
			return invalid(`{label} keys must be strings`)
		end
		result[key] = item
	end
	return result
end

local function catalogError(label: string): never
	error(`{CREDENTIAL_PATH}: invalid {label}`, 0)
end

local function stringList(value: unknown, label: string, pattern: string): { string }
	if type(value) ~= "table" then
		return catalogError(label)
	end
	local result: { string } = {}
	for index, item in value do
		if type(index) ~= "number" or index < 1 or index > #value or index % 1 ~= 0
			or type(item) ~= "string" or not item:match(pattern) or table.find(result, item) then
			return catalogError(label)
		end
		result[index] = item
	end
	return result
end

local function permissionMap(value: unknown, label: string): { [string]: string }
	local result: { [string]: string } = {}
	for name, access in record(value, label) do
		if not name:match("^[a-z_]+$") or (access ~= "read" and access ~= "write") then
			return catalogError(label)
		end
		result[name] = access
	end
	return result
end

local cachedText: string? = nil
local cachedCatalog: unknown = nil

local function readCatalog(): ({ [string]: Role }, { [string]: Profile }, { [string]: string }, { [string]: { [string]: string } })
	local source = Fs.readFileToString(CREDENTIAL_PATH)
	if source ~= cachedText then
		local environment: { [string]: string } = {}
		for _, key in { "PATH", "PATHEXT", "SystemRoot", "WINDIR", "TEMP", "TMP", "TMPDIR" } do
			environment[key] = Process.env[key]
		end
		local result = Process.run({ "node", "ci/github/authentication/catalog.cjs" }, { env = environment })
		if not result.ok then
			error(`{CREDENTIAL_PATH}: {result.stderr}`, 0)
		end
		cachedCatalog = Json.decode(result.stdout)
		cachedText = source
	end
	local root = record(cachedCatalog, CREDENTIAL_PATH)
	local roles: { [string]: Role } = {}
	local profiles: { [string]: Profile } = {}

	for id, raw in record(root.roles, CREDENTIAL_PATH .. " roles") do
		local label = `roles.{id}`
		local role = record(raw, label)
		local name = role.name
		if not id:match("^[a-z][a-z0-9_]*$") or type(name) ~= "string" or not name:match("^[%a_][%w_]*$")
			or name:lower():match("^gh[pousr]_") or name:lower():match("^github_pat_")
			or name:upper():match("^GITHUB_") then
			catalogError(label .. ".name")
		end
		local sources = stringList(role.sources, label .. ".sources", "^[a-z]+$")
		if #sources == 0 then
			catalogError(label .. ".sources")
		end
		for _, credentialSource in sources do
			if credentialSource ~= "secret" and credentialSource ~= "variable" then
				catalogError(label .. ".sources")
			end
		end
		local permissions = record(role.permissions, label .. ".permissions")
		roles[id] = {
			name = name :: string,
			selection = text(role.selection, label .. ".selection"),
			fallbackName = if type(role.fallbackName) == "string" then role.fallbackName else nil,
			sources = sources,
			permissions = {
				classic = stringList(permissions.classic, label .. ".permissions.classic", "^[%w_:]+$"),
				repository = permissionMap(permissions.repository, label .. ".permissions.repository"),
				organization = permissionMap(permissions.organization, label .. ".permissions.organization"),
			},
		}
	end

	for _, id in { "app_id", "app_private_key", "bootstrap_token", "projects_token", "rulesets_token" } do
		if not roles[id] then
			catalogError(`roles.{id}`)
		end
	end

	for id, raw in record(root.profiles, CREDENTIAL_PATH .. " profiles") do
		local label = `profiles.{id}`
		local profile = record(raw, label)
		local bootstrap = stringList(profile.bootstrap, label .. ".bootstrap", "^[a-z][a-z0-9_]*$")
		local delegate = profile.delegate
		if type(delegate) ~= "boolean" or (id ~= "source-ci" and (delegate or #bootstrap > 0)) then
			catalogError(label)
		end
		for _, role in bootstrap do
			if not roles[role] then
				catalogError(label .. ".bootstrap")
			end
		end
		local provider = profile.credentialProvider
		local oidc: Oidc? = nil
		if id == "source-ci" then
			if provider ~= "github-context" and provider ~= "oidc" and provider ~= "environment" then
				catalogError(label .. ".credentialProvider")
			end
			if provider == "oidc" then
				local settings = record(profile.oidc, label .. ".oidc")
				local endpoint, audience = settings.endpoint, settings.audience
				if type(endpoint) ~= "string" or not endpoint:match("^https://[^/%s]+") or endpoint:find("%s")
					or type(audience) ~= "string" or audience == "" or audience:find("[%c%s]") then
					catalogError(label .. ".oidc")
				end
				oidc = { endpoint = endpoint :: string, audience = audience :: string }
			end
		elseif provider ~= nil or profile.oidc ~= nil then
			catalogError(label .. ".credentialProvider")
		end
		profiles[id] = {
			bootstrap = bootstrap, delegate = delegate :: boolean,
			credentialProvider = provider :: ("github-context" | "oidc" | "environment")?, oidc = oidc,
			githubContext = profile.githubContext == true, usesCommands = profile.usesCommands == true,
			bootstrapEnvironment = if type(profile.bootstrapEnvironment) == "string" then profile.bootstrapEnvironment else nil,
			reportingEnvironment = if type(profile.reportingEnvironment) == "string" then profile.reportingEnvironment else nil,
			contextKeys = stringList(profile.contextKeys, label .. ".contextKeys", "^[%w_]+$"),
		}
	end
	for _, id in { "source-ci", "validate", "remote-read", "local" } do
		if not profiles[id] then
			catalogError(`profiles.{id}`)
		end
	end
	local neutralCheck = permissionMap(root.neutralCheck, "neutralCheck")
	if neutralCheck.checks ~= "write" then
		catalogError("neutralCheck.checks")
	end
	local environments: { [string]: { [string]: string } } = {}
	for name, rawBindings in record(root.environments or {}, "environments") do
		local bindings: { [string]: string } = {}
		for role, alias in record(rawBindings, name) do
			bindings[role] = text(alias, name .. "." .. role)
		end
		environments[name] = bindings
	end
	return roles, profiles, neutralCheck, environments
end

function Configuration.new(): Configuration
	local decoded: unknown = Toml.decode(Fs.readFileToString(CONFIG_PATH))
	local root = record(decoded, "configuration")
	local github = record(root.github, "github")
	local aliasSource = record(github.aliases, "github.aliases")
	local bootstrap = record(github.bootstrap, "github.bootstrap")
	local roles, profiles, neutralCheck, environments = readCatalog()
	local aliases: { [string]: string } = {}

	for name, value in aliasSource do
		if not name:match("^[%a][%w_-]*$") then
			return invalid("alias names must start with a letter and contain letters, digits, underscores, or hyphens")
		end
		local resolved = text(value, `github.aliases.{name}`)
		if not resolved:match("^[%w_.-]+$") and not resolved:match("^[%w_.-]+/[%w_.-]+$") then
			return invalid(`alias {name} must contain an owner or owner/repository path`)
		end
		aliases[name] = resolved
	end

	local enabled = bootstrap.enabled
	if type(enabled) ~= "boolean" then
		return invalid("github.bootstrap.enabled must be boolean")
	end
	local branchPrefix = text(bootstrap.branch_prefix, "github.bootstrap.branch_prefix")
	if not branchPrefix:match("^[%w][%w_/-]*$") or branchPrefix:find("//", 1, true) then
		return invalid("github.bootstrap.branch_prefix must be a safe Git branch prefix")
	end
	local credentials: { [string]: string } = {}

	for id, role in roles do
		credentials[id] = role.name
	end

	local publication: { [string]: boolean } = {}
	for name, value in record(github.publication, "github.publication") do
		if not name:match("^[a-z][a-z_]*$") or type(value) ~= "boolean" then
			return invalid("github.publication must map lowercase names to booleans")
		end
		publication[name] = value
	end

	local fields: Fields = {
		repository = text(github.repository, "github.repository"),
		aliases = aliases,
		enabled = enabled,
		branchPrefix = branchPrefix,
		credentials = credentials,
		roles = roles,
		profiles = profiles,
		neutralCheck = neutralCheck,
		environments = environments,
		publication = publication,
	}
	return setmetatable(fields, Configuration)
end

function Configuration.ResolveRepository(self: Configuration, reference: string): string
	local resolved = self.aliases[reference] or reference
	if not resolved:match("^[%w_.-]+/[%w_.-]+$") then
		return invalid(`{reference} must resolve to owner/repository`)
	end
	return resolved
end

function Configuration.ResolveOwner(self: Configuration, reference: string): string
	local resolved = self.aliases[reference] or reference
	if not resolved:match("^[%w_.-]+$") then
		return invalid(`{reference} must resolve to an owner`)
	end
	return resolved
end

return Configuration
