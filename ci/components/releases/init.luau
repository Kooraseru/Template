-- ci/components/releases/init.luau
--!strict

local ReleaseBuilder = require("@self/releaseBuilder")

local Component = {}
Component.__index = Component

type Fields = { releaseBuilder: ReleaseBuilder.ReleaseBuilder }

export type Component = setmetatable<Fields, typeof(Component)>

function Component.new(): Component
	local fields: Fields = { releaseBuilder = ReleaseBuilder.new() }
	return setmetatable(fields, Component)
end

function Component.Run(self: Component, _context: { event: string }): ()
	self.releaseBuilder:Run()
end

return Component
