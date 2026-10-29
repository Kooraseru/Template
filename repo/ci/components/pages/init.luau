-- repo/ci/components/pages/init.luau
--!strict

-- Coordinate the site assembly stage for the Pages component.
local SiteBuilder = require("@self/siteBuilder")

local Component = {}
Component.__index = Component

type ComponentFields = { siteBuilder: SiteBuilder.SiteBuilder }

export type Component = setmetatable<ComponentFields, typeof(Component)>

function Component.new(): Component
	local fields: ComponentFields = {
		siteBuilder = SiteBuilder.new(),
	}
	return setmetatable(fields, Component)
end

function Component.Run(self: Component, _context: { event: string }): ()
	self.siteBuilder:Run()
end

return Component
