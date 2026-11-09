-- ci/github/publication/gitFailure.luau
--!strict

--[[
	Classifies Git failures without echoing remote output, which can contain credentials. Specific GitHub rejections take precedence over the generic permission error.

	@param stderr string Raw Git error output. Never include it in the returned message.
	@return string A safe, actionable failure summary.
]]
local function classify(stderr: string): string
	if stderr:find("could not read Username", 1, true) or stderr:find("Authentication failed", 1, true) then
		return "Git HTTPS authentication failed; verify the scoped App/PAT token and credential helper"
	end

	if stderr:find("refusing to allow", 1, true) and stderr:find("workflow", 1, true) then
		return "GitHub rejected workflow file writes; verify Workflows: write permission"
	end

	if stderr:find("GH013", 1, true) or stderr:find("protected branch", 1, true) then
		return "GitHub rulesets or branch protection rejected the destination branch"
	end

	if stderr:find("Permission denied", 1, true) or stderr:find("403", 1, true) then
		return "GitHub rejected repository write permission for the destination branch"
	end

	if stderr:find("non-fast-forward", 1, true) then
		return "the destination branch already exists at an unexpected commit"
	end

	return "Git returned no recognized failure category; verify credentials and destination branch restrictions"
end

return classify
