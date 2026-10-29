-- ci/preflight/init.luau
--!strict

-- Coordinate configured provider analyzers and expose one Problems-compatible result.
local Contracts = require("@self/contracts")
local PlanBuilder = require("@self/planBuilder")
local ProviderDiscovery = require("@self/providerDiscovery")
local ProviderRunner = require("@self/providerRunner")
local Serde = require("@lune/serde")

local Preflight = {}
Preflight.__index = Preflight

export type Result = {
	tasks: { Contracts.Task },
	diagnostics: { Contracts.Diagnostic },
	passed: boolean,
}

type Fields = {
	planBuilder: PlanBuilder.PlanBuilder,
	providerDiscovery: ProviderDiscovery.ProviderDiscovery,
	providerRunner: ProviderRunner.ProviderRunner,
}

export type Preflight = setmetatable<Fields, typeof(Preflight)>

local function sortDiagnostics(diagnostics: { Contracts.Diagnostic }): ()
	table.sort(diagnostics, function(left: Contracts.Diagnostic, right: Contracts.Diagnostic): boolean
		if left.path ~= right.path then
			return left.path < right.path
		end
		if left.line ~= right.line then
			return left.line < right.line
		end
		if left.column ~= right.column then
			return left.column < right.column
		end
		return left.message < right.message
	end)
end

function Preflight.new(): Preflight
	local fields: Fields = {
		planBuilder = PlanBuilder.new(),
		providerDiscovery = ProviderDiscovery.new(),
		providerRunner = ProviderRunner.new(),
	}
	return setmetatable(fields, Preflight)
end

function Preflight.Run(self: Preflight, event: string): Result
	local plan = self.planBuilder:Build(event)
	local packages, discoveryDiagnostics = self.providerDiscovery:Discover()
	local diagnostics: { Contracts.Diagnostic } = {}
	for _, diagnostic in plan.diagnostics do
		table.insert(diagnostics, diagnostic)
	end
	for _, diagnostic in discoveryDiagnostics do
		table.insert(diagnostics, diagnostic)
	end

	local context: Contracts.Context = {
		event = event,
		planAvailable = plan.available,
		tasks = plan.tasks,
	}
	for _, diagnostic in self.providerRunner:Run(packages, context) do
		table.insert(diagnostics, diagnostic)
	end

	sortDiagnostics(diagnostics)
	local passed = true
	for _, diagnostic in diagnostics do
		print(`::diagnostic::{Serde.encode("json", diagnostic)}`)
		if diagnostic.severity == "error" then
			passed = false
		end
	end
	return { tasks = plan.tasks, diagnostics = diagnostics, passed = passed }
end

return Preflight
