-- .github/ci/components/distribution/attestations/publish/init.luau
--!strict

local Attestations = require("@ci/integrations/github/publication/attestations")
local Process = require("@lute/process")

local Component = {}
Component.__index = Component
export type Component = setmetatable<{}, typeof(Component)>

function Component.new(): Component
	return setmetatable({}, Component)
end

function Component.Run(self: Component, _: { event: string }): string?
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
