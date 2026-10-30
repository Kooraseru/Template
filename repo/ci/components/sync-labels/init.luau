-- repo/ci/components/sync-labels/init.luau
--!strict

local LabelCatalog = require("@self/labelCatalog")
local LabelSync = require("@self/labelSync")
local Publication = require("@ci/github/publication")

local Component = {}
Component.__index = Component
export type Component = setmetatable<{}, typeof(Component)>

function Component.new(): Component
	return setmetatable({}, Component)
end

function Component.Run(_self: Component, _context: { event: string }): string?
	local labels = LabelCatalog.Read()
	if #labels == 0 then
		return "skipped"
	end
	local repository = Publication.Begin("LABELS")
	if not repository then
		return "skipped"
	end
	if not LabelSync.Sync(repository, labels, Publication.Request) then
		return "skipped"
	end
	return nil
end

return Component
