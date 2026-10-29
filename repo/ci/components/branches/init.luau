-- repo/ci/components/branches/init.luau
--!strict

local BranchBuilder = require("@self/branchBuilder")

local Component = {}
Component.__index = Component

type Fields = { branchBuilder: BranchBuilder.BranchBuilder }

export type Component = setmetatable<Fields, typeof(Component)>

function Component.new(): Component
	local fields: Fields = { branchBuilder = BranchBuilder.new() }
	return setmetatable(fields, Component)
end

function Component.Run(self: Component, _context: { event: string }): ()
	self.branchBuilder:Run()
end

return Component
