-- repo/ci/components/plan-projects/init.luau
--!strict

local Fs = require("@lune/fs")
local Serde = require("@lune/serde")
local ProjectCatalog = require("@ci/github/projectCatalog")

local Component = {}
Component.__index = Component
export type Component = setmetatable<{}, typeof(Component)>

function Component.new(): Component
	return setmetatable({}, Component)
end

function Component.Run(_self: Component, _context: { event: string }): ()
	local projects = ProjectCatalog.Read()
	Fs.writeDir("build/repo/project-plans")
	Fs.writeFile(
		"build/repo/project-plans/index.json",
		Serde.encode("json", {
			projects = projects,
			applied = false,
			note = "This is the definition plan; sync-projects applies it using configured App/PAT authorization.",
		})
	)
	print(
		`Validated {#projects} project blueprints. This step generates a plan; remote application is handled by sync-projects.`
	)
end

return Component
