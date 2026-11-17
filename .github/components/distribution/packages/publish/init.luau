-- ci/components/distribution/packages/publish/init.luau
--!strict

const Publication = require("@ci/github/publication")
const Fs = require("@std/fs")
const Json = require("@formats/json")
const ConflictPolicy = require("@ci/github/publication/conflictPolicy")

local Component = {}
Component.__index = Component
export type Component = setmetatable<{}, typeof(Component)>

function Component.new(): Component
	return setmetatable({}, Component)
end

function Component.Run(self: Component, _: { event: string }): string?
	local index = Publication.Record(Json.decode(Fs.readFileToString("build/github/packages/index.json")))
	local policy = ConflictPolicy.Parse(index.onExisting, "Staged packages")
	print(`GitHub Packages existing-version policy: {policy}`)
	-- GitHub Packages is separate from Releases and release attachments.
	-- Unconfigured sample outputs exercise staging without inventing a registry format.
	for _, value in Publication.ReadIndex("build/github/packages/index.json", "packages") do
		local package = Publication.Record(value)
		local name = Publication.Text(package.name)

		if not package.format or not package.repository or not package.version then
			print(
				`Package {name}: registry publication skipped; configure format, version, and repository in .github/config/publishing/packages/{name}/package.toml`
			)
			continue
		end

		local repository = Publication.Begin("PACKAGES")
		if not repository then
			return "skipped"
		end
		error(
			`Package {name}: GitHub Packages adapter for {Publication.Text(package.format)} is not installed; staging does not create a registry package`,
			0
		)
	end
	return "skipped"
end

return Component
