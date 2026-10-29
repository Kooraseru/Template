-- repo/ci/preflight/providers/lune/init.luau
--!strict

local Contracts = require("@ci/preflight/contracts")
local RequireGraph = require("@self/requireGraph")

local LuneProvider = {}
LuneProvider.__index = LuneProvider

type Fields = { requireGraph: RequireGraph.Analyzer }

export type LuneProvider = setmetatable<Fields, typeof(LuneProvider)>

function LuneProvider.new(_configuration: Contracts.ProviderPackage): LuneProvider
	local fields: Fields = { requireGraph = RequireGraph.new() }
	return setmetatable(fields, LuneProvider)
end

function LuneProvider.Analyze(self: LuneProvider, context: Contracts.Context): Contracts.ProviderResult
	if not context.planAvailable then
		return { diagnostics = {} }
	end
	local analysis = self.requireGraph:Analyze(context.tasks)
	return { diagnostics = analysis.diagnostics }
end

return LuneProvider
