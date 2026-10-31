-- repo/ci/components/prepare-attestations/init.luau
--!strict

local Attestations = require("@ci/github/attestations")

local Component = {}
Component.__index = Component
export type Component = setmetatable<{}, typeof(Component)>

function Component.new(): Component
	return setmetatable({}, Component)
end

function Component.Run(_self: Component, _context: { event: string }): string?
	if not Attestations.Prepare() then
		return "skipped"
	end
	return nil
end

return Component
