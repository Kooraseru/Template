-- repo/ci/entry.luau
--!strict

local Bootstrap = require("./bootstrap")
local Process = require("@lune/process")
local Credentials = require("@ci/github/credentials")
local BranchRun = require("@ci/github/branchRun")
local PagesDeployment = require("@ci/github/pagesDeployment")
local Attestations = require("@ci/github/attestations")
local Responses = require("@ci/github/responses")

local argumentIndex = if Process.args[1] == "--" then 2 else 1
local argument = Process.args[argumentIndex]
local preflightOnly = argument == "--preflight-only"
local component = if argument == "--component" then Process.args[argumentIndex + 1] else nil
local reportOnly = argument == "--report"
local credentialNames = argument == "--credential-names"
local cleanupBranch = argument == "--cleanup-branch"
local pagesOptions = argument == "--pages-options"
local attestationOptions = argument == "--attestation-options"
local attestationReport = argument == "--attestation-report"
if
	argument
	and not preflightOnly
	and not component
	and not reportOnly
	and not credentialNames
	and not cleanupBranch
	and not pagesOptions
	and not attestationOptions
	and not attestationReport
then
	error(
		"expected --preflight-only, --component <identity>, --report, --credential-names, --cleanup-branch, --pages-options, --attestation-options, --attestation-report, or no arguments",
		0
	)
end
local configuredEvent = Process.env.CI_EVENT
local event: string
if configuredEvent then
	event = configuredEvent
elseif preflightOnly or credentialNames then
	event = "workflow_dispatch"
else
	print("::error::CI_EVENT is required")
	return Process.exit(1)
end

local ok, problem = xpcall(function(): boolean
	if credentialNames then
		Credentials.ExportNames()
		return true
	end
	if cleanupBranch then
		BranchRun.Cleanup()
		return true
	end
	if attestationOptions then
		Attestations.Options()
		return true
	end
	if attestationReport then
		Attestations.Report()
		return true
	end
	if pagesOptions then
		PagesDeployment.Prepare()
		return true
	end
	if component then
		Responses.Prepare()
	end
	Bootstrap.new(event):Run(preflightOnly, component, reportOnly)
	return true
end, tostring)
if not ok then
	print(`::error::{problem}`)
	if
		not preflightOnly
		and not credentialNames
		and not Responses.Written()
		and (Process.env.CI_GRAPH_RUN ~= "true" or reportOnly)
	then
		Responses.Record("execution/error", Responses.Template("execution.error"), "failure")
		Responses.Write(if Process.env.CI_GRAPH_RUN == "true" then "execution" else "start", {
			color = "failure",
			result = "CI stopped before completion. Open the run logs for the reported error.",
		})
	end
	Process.exit(1)
end
