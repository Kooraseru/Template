-- repo/ci/components/packages/init.luau
--!strict

local PackageBuilder = require("@self/packageBuilder")

local Component = {}
Component.__index = Component

type Fields = { builder: PackageBuilder.PackageBuilder }

export type Component = setmetatable<Fields, typeof(Component)>

function Component.new(): Component
	return setmetatable({ builder = PackageBuilder.new() }, Component)
end

function Component.Run(self: Component, _context: { event: string }): ()
	self.builder:Run()
end

return Component
