-- ci/github/init.luau
--!strict

local Configuration = require("@ci/github/configuration")
local Bootstrap = require("@ci/bootstrap")
local Process = require("@lute/process")
local Credentials = require("@ci/github/authentication/credentials")
local BranchRun = require("@ci/github/resources/branches/branchRun")
local PagesDeployment = require("@ci/github/publication/pagesDeployment")
local Attestations = require("@ci/github/publication/attestations")
local Publication = require("@ci/github/publication")
local Responses = require("@ci/github/reporting/responses")

local GitHub = {}

--- Validate hosted entry routes before resolving names or starting the selected run.
local function hostedProfile(name: string): Configuration.Profile
	local event = Process.env.GITHUB_EVENT_NAME
	local source = Process.env.GITHUB_REF == "refs/heads/source"
	local allowed = if name == "source-ci"
		then (source or Process.env.ACT == "true") and (event == "push" or event == "workflow_dispatch")
		elseif name == "validate"
			then event == "workflow_dispatch" or (event == "pull_request" and (Process.env.ACT == "true" or Process.env.GITHUB_BASE_REF == "source"))
			else name == "remote-read" and source and event == "workflow_dispatch"

	local profile = Configuration.new().profiles[name]
	if not profile or not allowed then
		error(`CI profile {name} is unavailable for this event and ref`, 0)
	end
	return profile
end

function GitHub.Run(): ()
	local argumentIndex = if Process.args[2] == "--" then 3 else 2
	local argument = Process.args[argumentIndex]
	local component = if argument == "--component" then Process.args[argumentIndex + 1] else nil
	local profileCheck = argument == "--profile-check"
	local reportOnly = argument == "--report"
	local credentialProvider = argument == "--credential-provider"
	local credentialNames = argument == "--credential-names"
	local cleanupBranch = argument == "--cleanup-branch"
	local pagesOptions = argument == "--pages-options"
	local attestationOptions = argument == "--attestation-options"
	local attestationReport = argument == "--attestation-report"

	if
		argument
		and not component
		and not profileCheck
		and not reportOnly
		and not credentialProvider
		and not credentialNames
		and not cleanupBranch
		and not pagesOptions
		and not attestationOptions
		and not attestationReport
	then
		error(
			"expected --component <identity>, --report, --credential-names, --credential-provider, --profile-check, --cleanup-branch, --pages-options, --attestation-options, --attestation-report, or no arguments",
			0
		)
	end

	local configuredEvent = Process.env.CI_EVENT
	local event: string

	if configuredEvent then
		event = configuredEvent
	elseif credentialNames or credentialProvider or profileCheck then
		event = "workflow_dispatch"
	else
		print("::error::CI_EVENT is required")
		Process.exit(1)
	end

	local ok, problem = xpcall(function(): boolean
		local profileName = Process.env.CI_PROFILE
		if not argument and Process.env.CI_GRAPH_RUN ~= "true" then
			local operation = Process.env.CI_OPERATION or (if event == "push" then "build" else "validation")
			if operation ~= "validation" and operation ~= "build" and operation ~= "readiness" then error("Unknown CI operation", 0) end
			if event == "pull_request" and operation ~= "validation" then error("Pull requests permit Validation only", 0) end
			Process.env.CI_OPERATION = operation
			profileName = if operation == "build" then "source-ci" elseif operation == "readiness" then "remote-read" else "validate"
			Process.env.CI_PROFILE = profileName
		end
		local profile = if profileName then hostedProfile(profileName) else nil
		if profileCheck then
			if profileName ~= "remote-read" then
				error("--profile-check requires the remote-read profile", 0)
			end
			return true
		end
		if credentialProvider then
			if profileName ~= "source-ci" or not profile or not profile.credentialProvider then
				error("--credential-provider requires the source-ci profile", 0)
			end
			Publication.Output("provider", profile.credentialProvider)
			Publication.Output("context", tostring(profile.githubContext))
			return true
		end
		if credentialNames then
			Credentials.ExportNames(profile)
			return true
		end
		if profile and (profileName == "remote-read" or event ~= Process.env.GITHUB_EVENT_NAME
			or argument ~= nil) then
			error("Invalid entry command or event for the selected CI profile", 0)
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
		-- A manual run through the trusted source workflow has the same publication intent as a source push.
		local planEvent = if profileName == "source-ci" and event == "workflow_dispatch" then "push" else event
		Bootstrap.new(planEvent, profile):Run(component, reportOnly, profileName)
		return true
	end, tostring)
	if not ok then
		print(`::error::{problem}`)

		if not credentialNames and not credentialProvider and not profileCheck and not Responses.Written() and (Process.env.CI_GRAPH_RUN ~= "true" or reportOnly) then
			Responses.Record("execution/error", Responses.Template("execution.error"), "failure")
			Responses.Write(if Process.env.CI_GRAPH_RUN == "true" then "execution" else "start", {
				color = "failure",
				result = "CI stopped before completion. Open the run logs for the reported error.",
			})
		end

		Process.exit(1)
	end
end

return GitHub
