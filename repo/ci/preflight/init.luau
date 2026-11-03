-- repo/ci/preflight/init.luau
--!strict

-- Coordinate configured provider analyzers and expose one Problems-compatible result.
local Contracts = require("@self/contracts")
local Diagnostics = require("@self/diagnostics")
local PlanBuilder = require("@self/planning")
local ProviderDiscovery = require("@self/providers/providerDiscovery")
local ProviderRunner = require("@self/providers/providerRunner")
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

function Preflight.new(): Preflight
	local fields: Fields = {
		planBuilder = PlanBuilder.new(),
		providerDiscovery = ProviderDiscovery.new(),
		providerRunner = ProviderRunner.new(),
	}
	return setmetatable(fields, Preflight)
end

function Preflight.Plan(self: Preflight, event: string): PlanBuilder.Plan
	return self.planBuilder:Build(event)
end

function Preflight.Run(self: Preflight, event: string): Result
	print("::preflight-start::")
	local diagnosticTable = Diagnostics.new(function(snapshot: { Contracts.Diagnostic })
		print(`::diagnostics::{Serde.encode("json", snapshot)}`)
	end)

	local plan = self:Plan(event)
	diagnosticTable:Replace("planning", plan.diagnostics)
	local packages, discoveryDiagnostics = self.providerDiscovery:Discover()
	diagnosticTable:Replace("discovery", discoveryDiagnostics)

	local context: Contracts.Context = {
		event = event,
		planAvailable = plan.available,
		tasks = plan.tasks,
	}
	self.providerRunner:Run(packages, context, function(owner: string, entries: { Contracts.Diagnostic })
		diagnosticTable:Replace(owner, entries)
	end)
	local diagnostics = diagnosticTable:Snapshot()
	local passed = true
	for _, diagnostic in diagnostics do
		if diagnostic.severity == "error" then
			passed = false
		end
	end
	return { tasks = plan.tasks, diagnostics = diagnostics, passed = passed }
end

return Preflight
