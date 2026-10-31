-- repo/ci/preflight/providerDiscovery.luau
--!strict

local Fs = require("@lune/fs")
local Process = require("@lune/process")
local Serde = require("@lune/serde")
local Glob = require("@ci/bootstrap/glob")
local Contracts = require("./contracts")

local ProviderDiscovery = {}
ProviderDiscovery.__index = ProviderDiscovery

export type ProviderDiscovery = setmetatable<{}, typeof(ProviderDiscovery)>

local function appendDiagnostic(diagnostics: { Contracts.Diagnostic }, path: string, message: string): ()
	local diagnostic: Contracts.Diagnostic = {
		path = path,
		line = 1,
		column = 1,
		endColumn = 2,
		severity = "error",
		message = message,
	}
	table.insert(diagnostics, diagnostic)
end

function ProviderDiscovery.new(): ProviderDiscovery
	return setmetatable({}, ProviderDiscovery)
end

function ProviderDiscovery.Discover(self: ProviderDiscovery): ({ Contracts.ProviderPackage }, { Contracts.Diagnostic })
	local packages: { Contracts.ProviderPackage } = {}
	local diagnostics: { Contracts.Diagnostic } = {}
	if not Fs.isDir("repo/ci/preflight/providers") then
		appendDiagnostic(diagnostics, "repo/ci/preflight/providers", "missing provider package root")
		return packages, diagnostics
	end

	local tracked = Process.exec("git", { "ls-files", "--stage", "--", "repo/ci/preflight/providers" })
	if not tracked.ok then
		appendDiagnostic(
			diagnostics,
			"repo/ci/preflight/providers",
			`unable to inspect provider entries: {tracked.stderr}`
		)
		return packages, diagnostics
	end
	for line in tracked.stdout:gmatch("[^\r\n]+") do
		local mode, path = line:match("^(%d+)%s+[%da-fA-F]+%s+%d+\t(.+)$")
		if mode == "120000" or mode == "160000" then
			appendDiagnostic(
				diagnostics,
				path or "repo/ci/preflight/providers",
				"provider packages cannot contain symlinks or gitlinks"
			)
		end
	end

	for _, directory in Glob.Find("repo/ci/preflight/providers/*") do
		local identity = directory:match("([^/]+)$")
		local configPath = `repo/config/ci/preflight/{identity}.toml`
		local entryPath = `{directory}/init.luau`
		local function report(message: string)
			appendDiagnostic(diagnostics, configPath, message)
		end

		if not identity or not identity:match("^[a-z][A-Za-z0-9]*$") then
			report("provider directory must use a lower camelCase identity")
			continue
		end
		if not Fs.isDir(directory) then
			report("provider entries must be directories")
			continue
		end
		if not Fs.isFile(configPath) then
			report("provider requires its settings under repo/config/ci/preflight/")
			continue
		end
		if not Fs.isFile(entryPath) then
			report("provider package requires init.luau")
			continue
		end

		local decodedOk, decoded = xpcall(function(): unknown
			return Serde.decode("toml", Fs.readFile(configPath))
		end, tostring)
		if not decodedOk then
			report(`unable to parse provider config: {decoded}`)
			continue
		end
		if type(decoded) ~= "table" then
			report("provider config must contain a TOML table")
			continue
		end

		local raw: { [string]: unknown } = {}
		local validKeys = true
		for key, value in decoded do
			if type(key) ~= "string" then
				validKeys = false
				break
			end
			raw[key] = value
		end
		local provider = raw.provider
		local enabled = raw.enabled
		if not validKeys then
			report("provider config keys must be strings")
		elseif type(provider) ~= "string" then
			report("provider config must declare a provider string")
		elseif provider ~= identity then
			report(`provider field must match package identity '{identity}'`)
		elseif type(enabled) ~= "boolean" then
			report("provider config must declare enabled as a boolean")
		else
			table.insert(packages, {
				identity = identity,
				provider = provider,
				directory = directory,
				configPath = configPath,
				enabled = enabled,
				options = raw,
			})
		end
	end
	for _, configPath in Glob.Find("repo/config/ci/preflight/*.toml") do
		local identity = configPath:match("([^/]+)%.toml$")
		if not identity or not Fs.isFile(`repo/ci/preflight/providers/{identity}/init.luau`) then
			appendDiagnostic(diagnostics, configPath, "provider settings have no matching implementation")
		end
	end

	table.sort(packages, function(left: Contracts.ProviderPackage, right: Contracts.ProviderPackage): boolean
		return left.identity < right.identity
	end)
	table.sort(diagnostics, function(left: Contracts.Diagnostic, right: Contracts.Diagnostic): boolean
		if left.path ~= right.path then
			return left.path < right.path
		end
		return left.line < right.line
	end)
	return packages, diagnostics
end

return ProviderDiscovery
