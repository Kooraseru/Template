-- repo/ci/components/publish-packages/init.luau
--!strict

local Publication = require("@ci/github/publication")
local Fs = require("@lune/fs")
local Serde = require("@lune/serde")
local ConflictPolicy = require("@ci/github/conflictPolicy")

local Component = {}
Component.__index = Component
export type Component = setmetatable<{}, typeof(Component)>

function Component.new(): Component
	return setmetatable({}, Component)
end

function Component.Run(_self: Component, _context: { event: string }): ()
	local index = Publication.Record(Serde.decode("json", Fs.readFile("build/repo/packages/index.json")))
	local policy = ConflictPolicy.Parse(index.onExisting, "Staged packages")
	print(`GitHub Packages existing-version policy: {policy}`)
	-- GitHub Packages is separate from Releases and release attachments.
	-- Unconfigured sample outputs exercise staging without inventing a registry format.
	for _, value in Publication.ReadIndex("build/repo/packages/index.json", "packages") do
		local package = Publication.Record(value)
		local name = Publication.Text(package.name)
		if not package.format or not package.repository or not package.version then
			print(
				`Package {name}: registry publication skipped; configure format, version, and repository in repo/content/packages/records/{name}/package.toml`
			)
			continue
		end
		local repository = Publication.Begin("PACKAGES")
		if not repository then
			return
		end
		error(
			`Package {name}: GitHub Packages adapter for {Publication.Text(package.format)} is not installed; staging does not create a registry package`,
			0
		)
	end
end

return Component
