-- ci/components/build/init.luau
--!strict

local HostBuilder = require("@self/HostBuilder")

local Component = {}
Component.__index = Component

type ComponentContract = {
	provides: { string },
	requires: { string },
	inputs: { string },
	outputs: { string },
	events: { string },
	boundary: string,
	enabled: boolean,
}

local contract: ComponentContract = {
	provides = { "build.completed" },
	requires = {},
	inputs = { "source/main.c", "source/hosts/*/init.luau" },
	outputs = { "build/*.exe" },
	events = { "push", "pull_request", "workflow_dispatch" },
	boundary = "read",
	enabled = true,
}
Component.Contract = contract

type ComponentFields = {
	hostBuilder: HostBuilder.HostBuilder,
}

export type Component = setmetatable<ComponentFields, typeof(Component)>

function Component.new(): Component
	local fields: ComponentFields = {
		hostBuilder = HostBuilder.new(),
	}
	return setmetatable(fields, Component)
end

function Component.Run(self: Component, _context: { event: string }): ()
	self.hostBuilder:Run()
end

return Component
