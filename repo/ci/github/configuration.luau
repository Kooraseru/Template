-- repo/ci/github/configuration.luau
--!strict

local Fs = require("@lune/fs")
local Serde = require("@lune/serde")

const CONFIG_PATH = "repo/config/github.toml"

local Configuration = {}
Configuration.__index = Configuration

type Fields = {
	repository: string,
	aliases: { [string]: string },
	enabled: boolean,
	branchPrefix: string,
	credentials: { [string]: string },
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

local function credentialName(value: unknown, label: string): string
	local name = text(value, label)
	if not name:match("^[%a_][%w_]*$") or name:match("^gh[pousr]_") or name:match("^github_pat_") then
		return invalid(`{label} must contain a GitHub secret/variable NAME, never an actual token or private key`)
	end
	return name
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

function Configuration.new(): Configuration
	local decoded: unknown = Serde.decode("toml", Fs.readFile(CONFIG_PATH))
	local root = record(decoded, "configuration")
	local github = record(root.github, "github")
	local aliasSource = record(github.aliases, "github.aliases")
	local bootstrap = record(github.bootstrap, "github.bootstrap")
	local credentialSource = record(github.credentials, "github.credentials")
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
	for role, name in credentialSource do
		if not role:match("^[%a][%w_]*$") then
			return invalid(`invalid credential role {role}`)
		end
		credentials[role] = credentialName(name, `github.credentials.{role}`)
	end
	local fields: Fields = {
		repository = text(github.repository, "github.repository"),
		aliases = aliases,
		enabled = enabled,
		branchPrefix = branchPrefix,
		credentials = credentials,
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
