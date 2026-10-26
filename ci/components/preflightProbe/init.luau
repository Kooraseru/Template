-- Temporary component used to verify Preflight diagnostics in VS Code.
-- Remove this package after confirming the Problems entry appears.
--!strict

local Component = {}
Component.__index = Component

Component.Contract = {
	provides = { "preflight.probe" },
	requires = {},
	inputs = { "source/missing-preflight-probe.c" },
	outputs = {},
	events = { "push", "pull_request", "workflow_dispatch" },
	boundary = "read",
	enabled = true,
}

export type Component = setmetatable<{}, typeof(Component)>

function Component.new(): Component
	return setmetatable({}, Component)
end

function Component.Run(_self: Component, _context: { event: string }): ()
	-- The probe intentionally has no runtime behavior.
end

return Component
