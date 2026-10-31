-- repo/ci/components/prepare-attestations/init.luau
--!strict

local Attestations = require("@ci/github/attestations")
local Process = require("@lune/process")

local Component = {}
Component.__index = Component
export type Component = setmetatable<{}, typeof(Component)>

function Component.new(): Component
	return setmetatable({}, Component)
end

function Component.Run(_self: Component, _context: { event: string }): string?
	if Process.env.CI_GRAPH_RUN ~= "true" then
		if Attestations.Enabled() then
			print("::warning::Attestations skipped: the generated CI execution workflow is unavailable")
		else
			print("Attestations skipped: disabled by configuration")
		end
		return "skipped"
	end
	if not Attestations.Prepare() then
		return "skipped"
	end
	return nil
end

return Component
