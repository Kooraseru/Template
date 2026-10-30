-- repo/ci/github/conflictPolicy.luau
--!strict

local ConflictPolicy = {}

export type Policy = "skip" | "fail" | "replace"
export type Decision = "create" | "skip" | "replace"

function ConflictPolicy.Parse(value: unknown, label: string): Policy
	if value == nil then
		return "replace"
	end
	if value ~= "skip" and value ~= "fail" and value ~= "replace" then
		error(`{label}: on_existing must be skip, fail, or replace`, 0)
	end
	return value
end

function ConflictPolicy.Resolve(policy: Policy, exists: boolean, replaceable: boolean, label: string): Decision
	if not exists then
		return "create"
	end
	if policy == "skip" then
		return "skip"
	end
	if policy == "fail" then
		error(`{label}: already exists (on_existing = fail)`, 0)
	end
	if not replaceable then
		error(`{label}: on_existing = replace cannot be honored by this destination or its protection rules`, 0)
	end
	return "replace"
end

return ConflictPolicy
