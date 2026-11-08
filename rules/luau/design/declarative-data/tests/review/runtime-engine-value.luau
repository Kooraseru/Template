-- global-rules/languages/luau/declarative-data/tests/review/runtime-engine-value.luau
--!strict

local function Create(runtimeObject: unknown)
	return { owner = runtimeObject }
end

return Create
