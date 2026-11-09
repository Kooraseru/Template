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
	reportingFailed: boolean?
): ()
	local identities: { string } = {}
	for identity in outcomes do
		table.insert(identities, identity)
	end
	table.sort(identities)
	local displayed: { [string]: string } = {}
	local failed = reportingFailed == true
	local skipped = false

	for _, identity in identities do
		local outcome = outcomes[identity]

		if outcome == "skipped" then
			local conclusion = SkipPolicy.Conclusion(identity)
			outcome = if conclusion == "neutral" and Process.env.ACT == "true"
				then "skipped (local run; no neutral Check Run created)"
				elseif conclusion == "neutral"
					then "skipped (separate Check Run: neutral)"
					else `skipped (configured job conclusion: {conclusion})`
		end

		displayed[identity] = outcome
		failed = failed or outcome:find("fail", 1, true) ~= nil or outcome == "blocked"
		skipped = skipped or outcome:find("skipped", 1, true) ~= nil
	end

	Responses.Write(if Process.env.CI_GRAPH_RUN == "true" then "execution" else "start", {
		selected_count = tostring(selectedCount),
		color = if failed then "failure" elseif skipped then "warning" else "success",
		result = if failed
			then "Some work failed or was blocked. Open its details below."
			elseif skipped
				then "Execution finished with skipped work. Review its outcome below."
				else "Selected components completed successfully.",
	}, displayed)
end

return Reporter
