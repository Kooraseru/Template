-- .github/ci/components/documentation/pages/publish/init.luau
--!strict

local PagesDeployment = require("@ci/integrations/github/publication/pagesDeployment")
local Process = require("@lute/process")

local Component = {}
Component.__index = Component
export type Component = setmetatable<{}, typeof(Component)>

function Component.new(): Component
	return setmetatable({}, Component)
end

function Component.Run(_self: Component, _context: { event: string }): string?
	if Process.env.CI_GRAPH_RUN ~= "true" then
		if Process.env.CI_PUBLISH_PAGES == "false" then
			print("Pages deployment skipped: disabled by configuration")
		else
			print("::warning::Pages deployment skipped: the generated CI execution workflow is unavailable")
		end
		return "skipped"
	end
	if not PagesDeployment.Prepare() then
		return "skipped"
	end
	return nil
end

return Component
