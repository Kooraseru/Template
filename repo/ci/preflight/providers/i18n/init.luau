-- repo/ci/preflight/providers/i18n/init.luau
--!strict

local Contracts = require("@ci/preflight/contracts")
local TagRenderer = require("@ci/content/tagRenderer")

local I18nProvider = {}
I18nProvider.__index = I18nProvider

type Fields = { configuration: Contracts.ProviderPackage }

export type I18nProvider = setmetatable<Fields, typeof(I18nProvider)>

function I18nProvider.new(configuration: Contracts.ProviderPackage): I18nProvider
	local fields: Fields = { configuration = configuration }
	return setmetatable(fields, I18nProvider)
end

function I18nProvider.Analyze(_self: I18nProvider, _context: Contracts.Context): Contracts.ProviderResult
	local diagnostics: { Contracts.Diagnostic } = {}
	local roots = { "repo/content/docs", "repo/content/root" }
	for _, malformed in TagRenderer.FindMalformed(roots) do
		local diagnostic: Contracts.Diagnostic = {
			path = malformed.path,
			line = malformed.line,
			column = malformed.column,
			endColumn = malformed.endColumn,
			severity = "error",
			message = `malformed content tag: {malformed.token}`,
		}
		table.insert(diagnostics, diagnostic)
	end
	for _, missing in TagRenderer.FindMissing(roots) do
		local diagnostic: Contracts.Diagnostic = {
			path = missing.path,
			line = missing.line,
			column = missing.column,
			endColumn = missing.endColumn,
			severity = "error",
			message = `locale '{missing.locale}' is missing tag '{missing.tag}', referenced by {missing.templatePath}:{missing.templateLine}`,
		}
		table.insert(diagnostics, diagnostic)
	end
	return { diagnostics = diagnostics }
end

return I18nProvider
