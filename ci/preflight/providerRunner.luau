-- ci/preflight/providerRunner.luau
--!strict

local Contracts = require("./contracts")
local Glob = require("@ci/bootstrap/glob")

local ProviderRunner = {}
ProviderRunner.__index = ProviderRunner

export type ProviderRunner = setmetatable<{}, typeof(ProviderRunner)>

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

function ProviderRunner.new(): ProviderRunner
	return setmetatable({}, ProviderRunner)
end

function ProviderRunner.Run(
	self: ProviderRunner,
	packages: { Contracts.ProviderPackage },
	context: Contracts.Context
): { Contracts.Diagnostic }
	local providerEntries = Glob.Find("config/preflight/*/init.luau")
	local diagnostics: { Contracts.Diagnostic } = {}
	if #providerEntries ~= #packages then
		appendDiagnostic(
			diagnostics,
			"config/preflight",
			"configured provider entries do not match discovered provider packages"
		)
	end
	for _, package in packages do
		if not package.enabled then
			continue
		end

		local ok, failure = xpcall(function(): boolean
			if #providerEntries == 0 then
				error("no provider entry modules were discovered", 0)
			end
			local modulePath = `@workspace/{package.directory}`
			local loadedSuccessfully, loaded = xpcall(require, tostring, modulePath)
			if not loadedSuccessfully then
				error(`unable to load provider module: {loaded}`, 0)
			end
			if type(loaded) ~= "table" or type(loaded.new) ~= "function" then
				error("provider entry must return a class exposing new", 0)
			end

			local providerClass: Contracts.ProviderClass = loaded
			local provider = providerClass.new(package)
			local result = provider:Analyze(context)
			for _, diagnostic in result.diagnostics do
				diagnostic.source = package.provider
				table.insert(diagnostics, diagnostic)
			end
			return true
		end, tostring)

		if not ok then
			appendDiagnostic(
				diagnostics,
				`{package.directory}/init.luau`,
				`{package.provider} provider failed: {failure}`
			)
		end
	end
	return diagnostics
end

return ProviderRunner
