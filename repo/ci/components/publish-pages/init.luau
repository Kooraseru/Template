-- repo/ci/components/publish-pages/init.luau
--!strict

local PagesDeployment = require("@ci/github/pagesDeployment")

local Component = {}
Component.__index = Component
export type Component = setmetatable<{}, typeof(Component)>

function Component.new(): Component
	return setmetatable({}, Component)
end

function Component.Run(_self: Component, _context: { event: string }): string?
	if not PagesDeployment.Prepare() then
		return "skipped"
	end
	return nil
end

return Component
