-- ci/components/documentation/pages/publish/init.luau
--!strict

local PagesDeployment = require("@ci/github/publication/pagesDeployment")
local Configuration = require("@ci/github/configuration")
local Process = require("@lute/process")

local Component = {}
Component.__index = Component
export type Component = setmetatable<{}, typeof(Component)>

function Component.new(): Component
	return setmetatable({}, Component)
end

function Component.Run(self: Component, _: { event: string }): string?
	if Process.env.CI_GRAPH_RUN ~= "true" then
		if Configuration.new().publication.pages == false then
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
