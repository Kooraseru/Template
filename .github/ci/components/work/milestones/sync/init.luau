-- .github/ci/components/work/milestones/sync/init.luau
--!strict

local Fs = require("@std/fs")
local Process = require("@lute/process")
local Json = require("@formats/json")
local Publication = require("@ci/integrations/github/publication")
local Catalog = require("@ci/integrations/github/resources/milestones/milestoneCatalog")
local MilestoneSync = require("@ci/integrations/github/resources/milestones/milestoneSync")

local Component = {}
Component.__index = Component
export type Component = setmetatable<{}, typeof(Component)>

function Component.new(): Component
	return setmetatable({}, Component)
end

function Component.Run(_self: Component, _context: { event: string }): string?
	local index = Publication.Record(Json.decode(Fs.readFileToString("build/github/milestones/index.json")))
	if type(index.milestones) ~= "table" then
		error("Staged milestone plan is missing its milestones array", 0)
	end
	local milestones: { Catalog.Milestone } = {}
	for _, value in index.milestones do
		table.insert(milestones, Publication.Record(value) :: Catalog.Milestone)
	end
	if #milestones == 0 then
		Fs.createDirectory("build/github/milestone-sync", { makeParents = true })
		Fs.writeStringToFile("build/github/milestone-sync/index.json", '{"milestones":[],"applied":true,"changed":false}')
		print("No planned release milestones; GitHub was not contacted")
		return nil
	end
	local repository = Publication.Begin("MILESTONES")
	if not repository then
		return "skipped"
	end
	local token = Process.env.GH_TOKEN
	if not token or token == "" then
		error("Milestone synchronization requires the run-provided GITHUB_TOKEN with Issues: write", 0)
	end
	local receipts, changed = MilestoneSync.Sync(repository, token, milestones)
	Fs.createDirectory("build/github/milestone-sync", { makeParents = true })
	Fs.writeStringToFile(
		"build/github/milestone-sync/index.json",
		Json.encode({ milestones = receipts, applied = true, changed = changed })
	)
	if #receipts == 0 and not changed then
		return "skipped"
	end
	return nil
end

return Component
