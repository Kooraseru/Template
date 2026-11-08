-- global-rules/languages/luau/language/types/tests/invalid/any-annotations.luau
--!strict

type Input = any
local function read(input: any): unknown
	return input
end

return read
