-- repo/ci/components/build/init.luau
--!strict

local HostBuilder = require("@self/hostBuilder")

local Component = {}
Component.__index = Component

type ComponentFields = { hostBuilder: HostBuilder.HostBuilder }

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
