--!strict

local Fs = require("@lune/fs")
local Process = require("@lune/process")
local Serde = require("@lune/serde")
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
	local index = Publication.Record(Serde.decode("json", Fs.readFile("build/github/milestones/index.json")))
	if type(index.milestones) ~= "table" then
		error("Staged milestone plan is missing its milestones array", 0)
	end
	local milestones: { Catalog.Milestone } = {}
	for _, value in index.milestones do
		table.insert(milestones, Publication.Record(value) :: Catalog.Milestone)
	end
	if #milestones == 0 then
		Fs.writeDir("build/github/milestone-sync")
		Fs.writeFile("build/github/milestone-sync/index.json", '{"milestones":[],"applied":true,"changed":false}')
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
	Fs.writeDir("build/github/milestone-sync")
	Fs.writeFile(
		"build/github/milestone-sync/index.json",
		Serde.encode("json", { milestones = receipts, applied = true, changed = changed })
	)
	if #receipts == 0 and not changed then
		return "skipped"
	end
	return nil
end

return Component
