-- fabricator/coverage.luau
--!strict

local Coverage = {}

--# Types

export type Target = { runner: string }
export type Decision = { Execute: boolean, Reason: string? }

--# Functions

function Coverage.Local(target: Target): Decision

	if target.runner:match("^ubuntu") then
		return { Execute = true }
	end

	return {
		Execute = false,
		Reason = "Native runner unavailable through local act: " .. target.runner .. "; build remains unverified",
	}
end

return Coverage
