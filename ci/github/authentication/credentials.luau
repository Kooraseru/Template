-- ci/github/authentication/credentials.luau
--!strict

local Process = require("@lute/process")
local Json = require("@formats/json")
local Fs = require("@std/fs")
local Configuration = require("@ci/github/configuration")
local ProjectCatalog = require("@ci/github/resources/projects/projectCatalog")

local Credentials = {}
Credentials.__index = Credentials

type Fields = {
	secrets: { [string]: string },
	variables: { [string]: string },
	selected: { [string]: string }?,
	inventory: { secrets: string?, variables: string?, roles: { string }, oidcToken: string?, oidcUrl: string? }?,
}
export type Credentials = setmetatable<Fields, typeof(Credentials)>

-- This is the native workflow transport contract, not a secret-name registry.
-- Actual secret names are read exclusively from .github/config/credentials.json.
local SECRET_ROLES: { [string]: string } = {
	app_id = "CI_GITHUB_APP_ID_SECRET",
	app_private_key = "CI_GITHUB_APP_PRIVATE_KEY",
	bootstrap_token = "CI_GITHUB_BOOTSTRAP_TOKEN",
	projects_token = "CI_GITHUB_PROJECTS_TOKEN",
	rulesets_token = "CI_GITHUB_RULESETS_TOKEN",
}

--- Decode a credential map without echoing values from malformed input.
local function decodeMap(encoded: string?, label: string): { [string]: string }
	if not encoded then
		return {}
	end
	local ok, decoded = pcall(Json.decode, encoded)
	if not ok or type(decoded) ~= "table" then
		error(`Invalid {label} credential map`, 0)
	end
	local result: { [string]: string } = {}
	for key, value in decoded do
		if type(key) ~= "string" or type(value) ~= "string" then
			error(`Invalid {label} credential map`, 0)
		end
		result[key] = value
	end
	return result
end

--- Register the selected value for GitHub log redaction.
local function mask(value: string): ()
	if Process.env.GITHUB_ACTIONS == "true" then
		local escaped = value:gsub("%%", "%%25"):gsub("\r", "%%0D"):gsub("\n", "%%0A")
		print("::add-mask::" .. escaped)
	end
end

function Credentials.new(profile: Configuration.Profile?): Credentials
	local encodedSecrets = Process.env.CI_SECRETS
	local encodedVariables = Process.env.CI_VARIABLES
	local delegatedRoles = Process.env.CI_SELECTOR_ROLES
	Process.env.CI_SECRETS = nil
	Process.env.CI_VARIABLES = nil
	Process.env.CI_SELECTOR_ROLES = nil

	local configuration = Configuration.new()
	local supplied: { [string]: string } = {}

	for role, environment in SECRET_ROLES do
		local value = Process.env[environment]
		Process.env[environment] = nil
		if value and value ~= "" and (not profile or table.find(profile.bootstrap, role)) then
			supplied[role] = value
		end
	end

	local appIdVariable = Process.env.CI_GITHUB_APP_ID_VARIABLE
	Process.env.CI_GITHUB_APP_ID_VARIABLE = nil
	-- Never consume or forward legacy blanket credential snapshots.
	Process.env.CI_GITHUB_SECRETS = nil
	Process.env.CI_GITHUB_VARIABLES = nil

	for role in configuration.credentials do
		local environment = "CI_CREDENTIAL_" .. role:upper()
		local value = Process.env[environment]
		Process.env[environment] = nil
		if value and value ~= "" and (not profile or table.find(profile.bootstrap, role)) then
			supplied[role] = value
		end
	end

	local fields: Fields = { secrets = {}, variables = {} }

	for role, value in supplied do
		local name = configuration.credentials[role]
		if name then
			fields.secrets[name:upper()] = value
		end
	end

	local appIdName = configuration.credentials.app_id
	if appIdName and appIdVariable and appIdVariable ~= "" and (not profile or table.find(profile.bootstrap, "app_id")) then
		fields.variables[appIdName:upper()] = appIdVariable
	end
	if profile and profile.githubContext and not profile.usesCommands then
		local secrets = decodeMap(encodedSecrets, "GitHub secrets")
		local variables = decodeMap(encodedVariables, "GitHub variables")
		for _, id in profile.bootstrap do
			local role = configuration.roles[id]
			if role.selection ~= "named" then
				continue
			end
			local name = role.name:upper()
			for _, source in role.sources do
				local value = if source == "secret" then secrets[name] else variables[name]
				if value and value ~= "" then
					mask(value)
					local destination = if source == "secret" then fields.secrets else fields.variables
					destination[name] = value
					break
				end
			end
		end
	end

	local active = if profile and profile.credentialProvider then profile
		elseif delegatedRoles and Process.env.CI_GRAPH_RUN == "true" then configuration.profiles["source-ci"]
		else nil
	if active and Process.env.ACT ~= "true" then
		local roles = if profile then profile.bootstrap else (delegatedRoles or ""):split(",")
		for _, id in roles do
			if not configuration.roles[id] then
				error("Invalid requested credential role", 0)
			end
		end
		fields.inventory = {
			secrets = encodedSecrets, variables = encodedVariables, roles = roles,
			oidcToken = Process.env.ACTIONS_ID_TOKEN_REQUEST_TOKEN,
			oidcUrl = Process.env.ACTIONS_ID_TOKEN_REQUEST_URL,
		}
		if active.oidc then
			table.clear(fields.secrets)
			table.clear(fields.variables)
		end
	end
	Process.env.ACTIONS_ID_TOKEN_REQUEST_TOKEN = nil
	Process.env.ACTIONS_ID_TOKEN_REQUEST_URL = nil
	return setmetatable(fields, Credentials)
end

function Credentials.ExportNames(profile: Configuration.Profile?): ()
	local destination = Process.env.GITHUB_OUTPUT
	if not destination then
		error("GITHUB_OUTPUT is required to resolve configured credential names", 0)
	end
	local configuration = Configuration.new()
	local roles: { string } = {}
	for role in configuration.credentials do
		if not profile or table.find(profile.bootstrap, role) then
			table.insert(roles, role)
		end
	end
	table.sort(roles)
	local lines: { string } = {}
	for _, role in roles do
		local entry = configuration.roles[role]
		if entry.selection == "capability" and not entry.fallbackName then
			continue
		end
		table.insert(lines, `{role}={entry.name}`)
		if profile then
			for _, source in entry.sources do
				table.insert(lines, `{role}_{source}={entry.name}`)
			end
		end
	end
	if #lines == 0 then
		return
	end
	local current = if Fs.exists(destination) and Fs.type(destination) == "file" then Fs.readFileToString(destination) else ""
	local separator = if current ~= "" and current:sub(-1) ~= "\n" then "\n" else ""
	Fs.writeStringToFile(destination, current .. separator .. table.concat(lines, "\n") .. "\n")
end

--- Resolve the job inventory once and discard the context before invoking task code.
function Credentials.Resolve(self: Credentials, configuration: Configuration.Configuration): ()
	local inventory = self.inventory
	if not inventory then
		return
	end
	self.inventory = nil
	local requests: { { role: string, operation: string, target: string, targets: { string }?, service: string } } = {}
	local repository = configuration:ResolveRepository(configuration.repository)
	local wanted: { [string]: boolean } = {}
	for _, key in configuration.profiles["source-ci"].contextKeys do
		wanted[key:upper()] = true
	end
	for _, id in inventory.roles do
		local role = configuration.roles[id]
		if role.selection == "named" or role.fallbackName then
			wanted[role.name:upper()] = true
		end
		local targets: { string }? = nil
		if id == "projects_token" then
			local owners: { string } = {}
			local defaultOwner = repository:match("^([^/]+)/")
			if defaultOwner then
				table.insert(owners, defaultOwner)
			end
			for _, project in ProjectCatalog.Read() do
				if not table.find(owners, project.owner) then
					table.insert(owners, project.owner)
				end
			end
			table.sort(owners)
			targets = owners
		end
		table.insert(requests, {
			role = id,
			operation = Process.env.CI_COMPONENT or "bootstrap",
			target = repository,
			targets = targets,
			service = "github",
		})
	end
	local environment: { [string]: string } = {}
	for _, key in { "PATH", "PATHEXT", "SystemRoot", "WINDIR", "TEMP", "TMP", "TMPDIR", "GITHUB_API_URL",
		"GITHUB_SERVER_URL", "GH_TOKEN" } do
		environment[key] = Process.env[key]
	end
	environment.ACTIONS_ID_TOKEN_REQUEST_TOKEN = inventory.oidcToken
	environment.ACTIONS_ID_TOKEN_REQUEST_URL = inventory.oidcUrl
	local secrets: { [string]: string } = {}
	local variables: { [string]: string } = {}
	for key, value in decodeMap(inventory.secrets, "GitHub secrets") do
		if wanted[key:upper()] or value:match("^ghp_[%w]+$") or value:match("^github_pat_[%w_]+$") then
			secrets[key] = value
		end
	end
	for key, value in decodeMap(inventory.variables, "GitHub variables") do
		if wanted[key:upper()] then
			variables[key] = value
		end
	end
	environment.CI_SELECTOR_REQUEST = Json.encode({
		profile = "source-ci",
		requests = requests,
		secrets = secrets,
		variables = variables,
	})
	local options: Process.ProcessRunOptions = { env = environment, timeout = 120 }
	local ok, result = pcall(Process.run, { "node", "ci/github/authentication/selector.cjs" }, options)
	if not ok or not result.ok then
		error("Credential selection failed. Check the configured source and verifier.", 0)
	end
	local decoded = Json.decode(result.stdout)
	if type(decoded) ~= "table" then
		error("Invalid credential selector response", 0)
	end
	local envelope = decoded :: { [string]: unknown }
	local values, reports = envelope.credentials, envelope.evidence
	if type(values) ~= "table" or type(reports) ~= "table" then
		error("Invalid credential selector response", 0)
	end
	local selected: { [string]: string } = {}
	for id, value in values do
		if type(id) ~= "string" or not table.find(inventory.roles, id) or type(value) ~= "string" then
			error("Invalid selected credential role", 0)
		end
		mask(value)
		selected[id] = value
	end
	self.selected = selected
	for _, request in requests do
		local evidence = (reports :: { [string]: unknown })[request.role]
		if type(evidence) == "table" then
			local detail = evidence :: { [string]: unknown }
			local state = if detail.state == "verified" then "verified" else "no verified candidate"
			local target = if (evidence :: { [string]: unknown }).targetAccess == "observed" then "observed" else "unverified"
			local destination = if request.targets then table.concat(request.targets, ", ") else request.target
			local counts = detail.counts
			local failures = ""
			if type(counts) == "table" then
				local tally = counts :: { [string]: unknown }
				failures = ` (invalid {tostring(tally.invalid)}, insufficient {tostring(tally.insufficient)}, unverified {tostring(tally.unverified)})`
			end
			print(`::notice::{request.operation}: {request.role} for {destination}, credential evidence {state}, target access {target}{failures}`)
		end
	end
end

function Credentials.Get(
	self: Credentials,
	configuration: Configuration.Configuration,
	role: string,
	secretOnly: boolean?
): string?
	if self.inventory and (configuration.roles[role].selection == "capability"
		or configuration.profiles["source-ci"].credentialProvider == "oidc" or configuration.profiles["source-ci"].usesCommands) then
		self:Resolve(configuration)
	end
	if self.selected and self.selected[role] then
		return self.selected[role]
	end
	local name = configuration.credentials[role]
	if not name then
		return nil
	end
	name = name:upper()
	if secretOnly then
		return self.secrets[name]
	end
	return self.secrets[name] or self.variables[name]
end

function Credentials.Environment(self: Credentials, roles: { string }): { [string]: string }
	local configuration = Configuration.new()
	self:Resolve(configuration)
	local result: { [string]: string } = {}
	for _, role in roles do
		local value = self:Get(configuration, role)
		local binding = "CI_CREDENTIAL_" .. role:upper()
		result[binding] = value or ""
		if self.selected and self.selected[role] and configuration.roles[role].selection == "capability" then
			result[binding .. "_VERIFIED"] = "true"
		end
	end
	return result
end

--- Explain unavailable credential options after a task has tried its own fallback chain.
function Credentials.WarnUnavailable(
	self: Credentials, configuration: Configuration.Configuration, profile: string, task: string, roles: { string }
): ()
	for _, id in roles do
		local role = configuration.roles[id]
		if self:Get(configuration, id) then
			continue
		end
		local requirements: { string } = {}
		for name, access in role.permissions.repository do
			table.insert(requirements, `repository {name}: {access}`)
		end
		for name, access in role.permissions.organization do
			table.insert(requirements, `organization {name}: {access}`)
		end
		for _, scope in role.permissions.classic do
			table.insert(requirements, `classic PAT scope {scope}`)
		end
		table.sort(requirements)
		local details = if #requirements == 0 then "" else " (" .. table.concat(requirements, ", ") .. ")"
		print(`::warning::{task} on {profile}: credential {role.name} is unavailable{details}`)
	end
end

function Credentials.Describe(self: Credentials, configuration: Configuration.Configuration): ()
	local secretNames: { string } = {}
	local variableNames: { string } = {}
	for name in self.secrets do
		table.insert(secretNames, name)
	end
	for name in self.variables do
		table.insert(variableNames, name)
	end
	table.sort(secretNames)
	table.sort(variableNames)
	local roles: { string } = {}
	for role in configuration.credentials do
		table.insert(roles, role)
	end
	table.sort(roles)
	print("::group::GitHub credential availability (names only)")
	print("Available selected secret names: " .. (if #secretNames > 0 then table.concat(secretNames, ", ") else "none"))
	print(
		"Available selected variable names: "
			.. (if #variableNames > 0 then table.concat(variableNames, ", ") else "none")
	)

	for _, role in roles do
		local name = configuration.credentials[role]
		local location = if self.secrets[name:upper()]
			then "secret available"
			elseif self.variables[name:upper()]
				then "variable available"
				elseif not SECRET_ROLES[role] then "not requested by bootstrap" else "not available to this run"
		print(`{role} -> {name}: {location}`)
	end

	print("Values are resolved from GitHub at runtime; credentials.json contains names, never credentials.")
	print("::endgroup::")
end

return Credentials
