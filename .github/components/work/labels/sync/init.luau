-- ci/components/work/labels/sync/init.luau
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

function Component.Run(self: Component, _: { event: string }): string?
	local labels = LabelCatalog.Read()
	local repository = Publication.Begin("LABELS")
	if not repository then
		return "skipped"
	end
	if not LabelSync.Sync(repository, labels, Publication.Request) then
		print("GitHub labels already match the catalog; reconciliation completed successfully")
	end
	return nil
end

return Component
