-- global-rules/languages/luau/declarative-data/tests/review/external-mutation.luau
--!strict

local function Configure(updateExternal: ({ [string]: boolean }) -> ()): { [string]: boolean }
	const configuration = { enabled = true }
	updateExternal(configuration)
	return configuration
end

return Configure
