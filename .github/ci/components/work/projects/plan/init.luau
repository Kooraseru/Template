-- .github/ci/components/work/projects/plan/init.luau
--!strict

local Fs = require("@std/fs")
local Json = require("@formats/json")
local ProjectCatalog = require("@ci/integrations/github/resources/projects/projectCatalog")

local Component = {}
Component.__index = Component
export type Component = setmetatable<{}, typeof(Component)>

function Component.new(): Component
	return setmetatable({}, Component)
end

function Component.Run(self: Component, _: { event: string }): ()
	local projects = ProjectCatalog.Read()
	Fs.createDirectory("build/github/project-plans", { makeParents = true })
	Fs.writeStringToFile(
		"build/github/project-plans/index.json",
		Json.encode({
			projects = projects,
			applied = false,
			note = "Validated definition snapshot only; projects/sync re-reads the source definitions and reconciles GitHub Projects using configured App/PAT authorization.",
		})
	)
	print(
		`Validated {#projects} project blueprints. This read-only definition snapshot does not change GitHub Projects; projects/sync handles synchronization.`
	)
end

return Component
