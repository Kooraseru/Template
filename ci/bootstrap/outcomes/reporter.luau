-- ci/bootstrap/outcomes/reporter.luau
--!strict

local Process = require("@lute/process")
local SkipPolicy = require("@ci/bootstrap/outcomes/skipPolicy")
local Responses = require("@ci/github/reporting/responses")

local Reporter = {}
Reporter.__index = Reporter

export type Reporter = setmetatable<{}, typeof(Reporter)>

function Reporter.new(): Reporter
	return setmetatable({}, Reporter)
end

function Reporter.Report(
	self: Reporter,
	outcomes: { [string]: string },
	selectedCount: number,
	reportingFailed: boolean?,
	suppressNeutral: boolean?
): ()
	local identities: { string } = {}
	for identity in outcomes do
		table.insert(identities, identity)
	end
	table.sort(identities)
	local displayed: { [string]: string } = {}
	local failed = reportingFailed == true
	local skippedWithWarning = false
	local acceptedSkip = false

	for _, identity in identities do
		local outcome = outcomes[identity]

		if outcome == "skipped" then
			local conclusion = SkipPolicy.Conclusion(identity)
			skippedWithWarning = skippedWithWarning or conclusion ~= "success"
			acceptedSkip = acceptedSkip or conclusion == "success"
			outcome = if conclusion == "neutral" and Process.env.ACT == "true"
				then "skipped (local run; no neutral Check Run created)"
				elseif conclusion == "neutral" and suppressNeutral then "skipped (no separate Check Run for this profile)"
				elseif conclusion == "neutral"
					then "skipped (separate Check Run: neutral)"
					else `skipped (configured job conclusion: {conclusion})`
		elseif outcome:find("skipped", 1, true) then
			skippedWithWarning = true
		end

		displayed[identity] = outcome
		failed = failed or Responses.FailedOutcome(outcome)
	end

	Responses.Write(if Process.env.CI_GRAPH_RUN == "true" then "execution" else "start", {
		selected_count = tostring(selectedCount),
		color = if failed then "failure" elseif skippedWithWarning then "warning" else "success",
		result = if failed
			then "Some work failed or was blocked. Review what needs attention below."
			elseif skippedWithWarning
				then "Execution finished with skipped work. Review its outcome below."
			elseif acceptedSkip then "Selected components completed successfully or had an accepted skip."
			else "Selected components completed successfully.",
	}, displayed)
end

return Reporter
