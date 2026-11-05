-- .github/ci/components/work/projects/plan/init.luau
--!strict

local Fs = require("@lune/fs")
local Serde = require("@lune/serde")
local ProjectCatalog = require("@ci/integrations/github/resources/projects/projectCatalog")

local Component = {}
Component.__index = Component
export type Component = setmetatable<{}, typeof(Component)>

function Component.new(): Component
	return setmetatable({}, Component)
end

function Component.Run(_self: Component, _context: { event: string }): ()
	local projects = ProjectCatalog.Read()
	Fs.writeDir("build/github/project-plans")
	Fs.writeFile(
		"build/github/project-plans/index.json",
		Serde.encode("json", {
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
