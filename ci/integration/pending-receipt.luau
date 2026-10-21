-- .github/integration/pending-receipt.luau
--!strict

local PendingReceipt = {}

--# Modules

local Process = require("@lune/process")
local Request = require("./request")
local Rules = require("../../libraries/registry/rules")

--# Functions

function PendingReceipt.Allowed(raw: unknown, env: Request.Environment?): boolean
	local selected = env or Process.env
	local run = Rules.Entries(raw)

	if
		selected.CI_PUBLICATION_JOB ~= "true"
		or selected.ACT == "true"
		or selected.GITHUB_ACTIONS ~= "true"
		or selected.GITHUB_SERVER_URL ~= "https://github.com"
		or selected.GITHUB_REF ~= "refs/heads/source"
		or (selected.GITHUB_EVENT_NAME ~= "workflow_dispatch" and selected.GITHUB_EVENT_NAME ~= "push")
	then
		return false
	end

	local operation = Request.Read(selected).operation

	return (operation == "Publish" or operation == "Full Run")
		and tostring(run.id) == selected.GITHUB_RUN_ID
		and run.status == "in_progress"
		and run.conclusion == nil
		and run.head_sha == selected.GITHUB_SHA
		and type(run.actor) == "table"
		and Rules.Entries(run.actor).login == selected.GITHUB_ACTOR
end

return PendingReceipt
