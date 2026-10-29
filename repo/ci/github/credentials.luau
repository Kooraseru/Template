-- repo/ci/github/credentials.luau
--!strict

local Process = require("@lune/process")
local Fs = require("@lune/fs")
local Configuration = require("./configuration")

local Credentials = {}
Credentials.__index = Credentials

type Fields = { secrets: { [string]: string }, variables: { [string]: string } }
export type Credentials = setmetatable<Fields, typeof(Credentials)>

-- This is the native workflow transport contract, not a secret-name registry.
-- Actual secret names are read exclusively from github.toml.
const SECRET_ROLES: { [string]: string } = {
	app_id = "CI_GITHUB_APP_ID_SECRET",
	app_private_key = "CI_GITHUB_APP_PRIVATE_KEY",
	bootstrap_token = "CI_GITHUB_BOOTSTRAP_TOKEN",
}

function Credentials.new(): Credentials
	local supplied: { [string]: string } = {}
	for role, environment in SECRET_ROLES do
		local value = Process.env[environment]
		Process.env[environment] = nil
		if value and value ~= "" then
			supplied[role] = value
		end
	end
	local appIdVariable = Process.env.CI_GITHUB_APP_ID_VARIABLE
	Process.env.CI_GITHUB_APP_ID_VARIABLE = nil
	-- Never consume or forward legacy blanket credential snapshots.
	Process.env.CI_GITHUB_SECRETS = nil
	Process.env.CI_GITHUB_VARIABLES = nil
	local configuration = Configuration.new()
	local fields: Fields = { secrets = {}, variables = {} }
	for role, value in supplied do
		local name = configuration.credentials[role]
		if name then
			fields.secrets[name:upper()] = value
		end
	end
	local appIdName = configuration.credentials.app_id
	if appIdName and appIdVariable and appIdVariable ~= "" then
		fields.variables[appIdName:upper()] = appIdVariable
	end
	return setmetatable(fields, Credentials)
end

function Credentials.ExportNames(): ()
	local destination = Process.env.GITHUB_OUTPUT
	if not destination then
		error("GITHUB_OUTPUT is required to resolve configured credential names", 0)
	end
	local configuration = Configuration.new()
	local roles: { string } = {}
	for role in configuration.credentials do
		table.insert(roles, role)
	end
	table.sort(roles)
	local lines: { string } = {}
	for _, role in roles do
		table.insert(lines, `{role}={configuration.credentials[role]}`)
	end
	local current = if Fs.isFile(destination) then Fs.readFile(destination) else ""
	Fs.writeFile(destination, current .. "\n" .. table.concat(lines, "\n") .. "\n")
end

function Credentials.Get(
	self: Credentials,
	configuration: Configuration.Configuration,
	role: string,
	secretOnly: boolean?
): string?
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
			else if self.variables[name:upper()]
				then "variable available"
				else if not SECRET_ROLES[role] then "not requested by bootstrap" else "not available to this run"
		print(`{role} -> {name}: {location}`)
	end
	print("Values are resolved from GitHub at runtime; TOML contains names, never credentials.")
	print("::endgroup::")
end

return Credentials
