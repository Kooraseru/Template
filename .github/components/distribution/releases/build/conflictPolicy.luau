-- .github/components/distribution/releases/build/conflictPolicy.luau
--!strict

local ConflictPolicy = {}

export type Policy = "skip" | "fail" | "replace"

--- Validate the configured conflict policy, defaulting to replacement.
function ConflictPolicy.Parse(value: unknown, label: string): Policy
	if value == nil then
		return "replace"
	end
	if value ~= "skip" and value ~= "fail" and value ~= "replace" then
		error(`{label}: on_existing must be skip, fail, or replace`, 0)
	end
	return value
end

return ConflictPolicy
