-- repo/ci/preflight/providers/luaurc/init.luau
--!strict

local Fs = require("@lune/fs")
local Serde = require("@lune/serde")
local Contracts = require("@ci/preflight/contracts")

local LuaurcProvider = {}
LuaurcProvider.__index = LuaurcProvider

type Fields = { configuration: Contracts.ProviderPackage }

export type LuaurcProvider = setmetatable<Fields, typeof(LuaurcProvider)>

local function diagnostic(path: string, message: string): Contracts.Diagnostic
	return {
		path = path,
		line = 1,
		column = 1,
		endColumn = 2,
		severity = "error",
		message = message,
	}
end

function LuaurcProvider.new(configuration: Contracts.ProviderPackage): LuaurcProvider
	local fields: Fields = { configuration = configuration }
	return setmetatable(fields, LuaurcProvider)
end

function LuaurcProvider.Analyze(self: LuaurcProvider, _context: Contracts.Context): Contracts.ProviderResult
	local file = self.configuration.options.file
	if type(file) ~= "string" or file == "" then
		return { diagnostics = { diagnostic(self.configuration.configPath, "luaurc provider requires a file path") } }
	end
	if not Fs.isFile(file) then
		return { diagnostics = { diagnostic(file, "configured Luau runtime config does not exist") } }
	end

	local decoded, configuration = xpcall(function(): unknown
		return Serde.decode("json", Fs.readFile(file))
	end, tostring)
	if not decoded then
		return { diagnostics = { diagnostic(file, `invalid JSON config: {configuration}`) } }
	end
	if type(configuration) ~= "table" or type(configuration.aliases) ~= "table" then
		return { diagnostics = { diagnostic(file, "luaurc must define an aliases table") } }
	end

	local aliases: { [string]: unknown } = {}
	for key, value in configuration.aliases do
		if type(key) == "string" then
			aliases[key] = value
		end
	end
	local required = self.configuration.options.requiredAliases
	if type(required) ~= "table" then
		return { diagnostics = { diagnostic(self.configuration.configPath, "requiredAliases must be a TOML array") } }
	end
	local diagnostics: { Contracts.Diagnostic } = {}
	for _, name in required do
		if type(name) ~= "string" then
			table.insert(diagnostics, diagnostic(self.configuration.configPath, "requiredAliases must contain strings"))
			continue
		end
		if type(aliases[name]) ~= "string" then
			table.insert(diagnostics, diagnostic(file, `missing string alias '{name}'`))
		end
	end
	return { diagnostics = diagnostics }
end

return LuaurcProvider
