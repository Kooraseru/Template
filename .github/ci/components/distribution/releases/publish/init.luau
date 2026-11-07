-- .github/ci/components/distribution/releases/publish/init.luau
--!strict

local Fs = require("@std/fs")
local Json = require("@formats/json")
local Publication = require("@ci/integrations/github/publication")
local ConflictPolicy = require("@ci/integrations/github/publication/conflictPolicy")
local ReleasePublisher = require("@self/releasePublisher")

local Component = {}
Component.__index = Component
export type Component = setmetatable<{}, typeof(Component)>

function Component.new(): Component
	return setmetatable({}, Component)
end

function Component.Run(_self: Component, _context: { event: string }): string?
	local index = Publication.Record(Json.decode(Fs.readFileToString("build/github/releases/index.json")))
	local policy = ConflictPolicy.Parse(index.onExisting, "Staged releases")
	local repository = Publication.Begin("RELEASES")
	if not repository then
		return "skipped"
	end
	local published = false
	for _, value in Publication.ReadIndex("build/github/releases/index.json", "releases") do
		if ReleasePublisher.Publish(repository, Publication.Record(value), policy, Publication.Request) then
			published = true
		end
	end
	if not published then
		return "skipped"
	end
	return nil
end

return Component
