--!strict

local Fs = require("@lune/fs")
local Serde = require("@lune/serde")
local Catalog = require("@ci/github/milestones/milestoneCatalog")

local Component = {}
Component.__index = Component
export type Component = setmetatable<{}, typeof(Component)>

function Component.new(): Component
	return setmetatable({}, Component)
end

function Component.Run(_self: Component, _context: { event: string }): ()
	local milestones = Catalog.Read()
	Fs.writeDir("build/github/milestones")
	local encoded = Serde.encode("json", {
		milestones = milestones,
		applied = false,
		note = "Validated milestone plan only; milestones/sync applies it to GitHub on source pushes.",
	})
	if #milestones == 0 then
		encoded = encoded:gsub('"milestones":{}', '"milestones":[]', 1)
	end
	Fs.writeFile("build/github/milestones/index.json", encoded)
	print(`Validated {#milestones} planned release milestones; release/build only reads release.entries.`)
end

return Component
