-- .github/ci/components/work/milestones/plan/init.luau
--!strict

local Fs = require("@std/fs")
local Json = require("@formats/json")
local Catalog = require("@ci/integrations/github/resources/milestones/milestoneCatalog")

local Component = {}
Component.__index = Component
export type Component = setmetatable<{}, typeof(Component)>

function Component.new(): Component
	return setmetatable({}, Component)
end

function Component.Run(self: Component, _: { event: string }): ()
	local milestones = Catalog.Read()
	Fs.createDirectory("build/github/milestones", { makeParents = true })
	local encoded = Json.encode({
		milestones = milestones,
		applied = false,
		note = "Validated milestone plan only; milestones/sync applies it to GitHub on source pushes.",
	})
	if #milestones == 0 then
		encoded = encoded:gsub('"milestones":{}', '"milestones":[]', 1)
	end
	Fs.writeStringToFile("build/github/milestones/index.json", encoded)
	print(`Validated {#milestones} planned release milestones independently of release records.`)
end

return Component
