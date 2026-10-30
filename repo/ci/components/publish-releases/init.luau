-- repo/ci/components/publish-releases/init.luau
--!strict

local Fs = require("@lune/fs")
local Serde = require("@lune/serde")
local Publication = require("@ci/github/publication")
local ConflictPolicy = require("@ci/github/conflictPolicy")
local ReleasePublisher = require("@self/releasePublisher")

local Component = {}
Component.__index = Component
export type Component = setmetatable<{}, typeof(Component)>

function Component.new(): Component
	return setmetatable({}, Component)
end

function Component.Run(_self: Component, _context: { event: string }): ()
	local index = Publication.Record(Serde.decode("json", Fs.readFile("build/repo/releases/index.json")))
	local policy = ConflictPolicy.Parse(index.onExisting, "Staged releases")
	local repository = Publication.Begin("RELEASES")
	if not repository then
		return
	end
	for _, value in Publication.ReadIndex("build/repo/releases/index.json", "releases") do
		ReleasePublisher.Publish(repository, Publication.Record(value), policy, Publication.Request)
	end
end

return Component
