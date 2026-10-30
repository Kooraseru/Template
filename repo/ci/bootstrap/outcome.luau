-- repo/ci/bootstrap/outcome.luau
--!strict

local Outcome = { skippedExitCode = 78 }

export type Value = "passed" | "skipped" | "failed"

function Outcome.FromReturn(value: unknown): Value
	if value == nil then
		return "passed"
	end
	if value == "skipped" then
		return "skipped"
	end
	error("Component.Run must return nil on completion or skipped when no work was performed", 0)
end

function Outcome.FromExitCode(code: number): Value
	if code == 0 then
		return "passed"
	end
	if code == Outcome.skippedExitCode then
		return "skipped"
	end
	return "failed"
end

return Outcome
