-- .github/components/work/maintenance.luau
--!strict

-- Validate configured records before any authorized write.
local Process = require("@lute/process")
local Publication = require("@formats/github")
local Labels = require("./labels/sync/labelCatalog")
local LabelSync = require("./labels/sync/labelSync")
local Milestones = require("./milestones/milestoneCatalog")
local MilestoneSync = require("./milestones/milestoneSync")

local labels = Labels.Read()
local milestones = Milestones.Read()
print(`Validated {#labels} labels and {#milestones} milestones`)
local mode = Process.env.MAINTENANCE_TARGET
if mode == nil or mode == "rehearse" then
	return
end
local repo = Process.env.GITHUB_REPOSITORY
local branch = Process.env.CI_DEFAULT_BRANCH
local token = Process.env.GH_TOKEN
if Process.env.GITHUB_ACTIONS ~= "true" or Process.env.GITHUB_EVENT_NAME ~= "workflow_dispatch"
	or Process.env.ACT == "true" or not repo or not branch or not token
	or Process.env.GITHUB_REF ~= `refs/heads/{branch}` then
	error("Maintenance writes require explicit default-branch GitHub Actions execution", 0)
end
if mode == "labels" then
	LabelSync.Sync(repo, labels, Publication.Request)
elseif mode == "milestones" then
	MilestoneSync.Sync(repo, token, milestones)
else
	error("Unknown maintenance target", 0)
end
