-- repo/ci/github/credentials.luau
--!strict

local Process = require("@lune/process")
local Serde = require("@lune/serde")
local Configuration = require("./configuration")

local Credentials = {}
Credentials.__index = Credentials

type Fields = { secrets: { [string]: string }, variables: { [string]: string } }
export type Credentials = setmetatable<Fields, typeof(Credentials)>

local function values(encoded: string?, label: string): { [string]: string }
	if not encoded or encoded == "" then
		return {}
	end
	local ok, decoded = xpcall(function(): unknown
		return Serde.decode("json", encoded)
	end, function(): nil
		return nil
	end)
	if not ok or type(decoded) ~= "table" then
		error(`{label} must contain a JSON object`, 0)
	end
	local result: { [string]: string } = {}
	for name, value in decoded do
		if type(name) ~= "string" or not name:match("^[%a_][%w_]*$") or type(value) ~= "string" then
			error(`{label} must contain string names and values`, 0)
		end
		if value ~= "" then
			result[name:upper()] = value
		end
	end
	return result
end

function Credentials.new(): Credentials
	local secrets = Process.env.CI_GITHUB_SECRETS
	local variables = Process.env.CI_GITHUB_VARIABLES
	-- Discovered components must not inherit the complete secret inventory.
	Process.env.CI_GITHUB_SECRETS = nil
	Process.env.CI_GITHUB_VARIABLES = nil
	local fields: Fields = {
		secrets = values(secrets, "CI_GITHUB_SECRETS"),
		variables = values(variables, "CI_GITHUB_VARIABLES"),
	}
	return setmetatable(fields, Credentials)
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
	print("Available secret names: " .. (if #secretNames > 0 then table.concat(secretNames, ", ") else "none"))
	print("Available variable names: " .. (if #variableNames > 0 then table.concat(variableNames, ", ") else "none"))
	for _, role in roles do
		local name = configuration.credentials[role]
		local location = if self.secrets[name:upper()]
			then "secret available"
			else if self.variables[name:upper()] then "variable available" else "not available to this run"
		print(`{role} -> {name}: {location}`)
	end
	print("Values are resolved from GitHub at runtime; TOML contains names, never credentials.")
	print("::endgroup::")
end

return Credentials
