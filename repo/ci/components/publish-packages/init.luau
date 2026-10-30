-- repo/ci/components/publish-packages/init.luau
--!strict

local Publication = require("@ci/github/publication")

local Component = {}
Component.__index = Component
export type Component = setmetatable<{}, typeof(Component)>

function Component.new(): Component
	return setmetatable({}, Component)
end

function Component.Run(_self: Component, _context: { event: string }): ()
	-- GitHub Packages is separate from Releases and release attachments.
	-- Unconfigured sample outputs exercise staging without inventing a registry format.
	for _, value in Publication.ReadIndex("build/repo/packages/index.json", "packages") do
		local package = Publication.Record(value)
		local name = Publication.Text(package.name)
		if not package.format or not package.repository then
			print(
				`Package {name}: registry publication skipped; configure format and repository in repo/content/packages/packages.toml`
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
