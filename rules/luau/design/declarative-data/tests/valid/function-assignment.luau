-- global-rules/languages/luau/declarative-data/tests/valid/function-assignment.luau
--!strict

const API = { version = "current" }
API.Run = function(value: number): number
	return value * 2
end

return API
