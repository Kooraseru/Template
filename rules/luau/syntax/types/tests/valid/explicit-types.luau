-- global-rules/languages/luau/language/types/tests/valid/explicit-types.luau
--!strict

type Input = { value: unknown }
local _note = "a type named any should not trigger this rule"
-- nor should comments mention any.
local function read(input: Input): unknown
	return input.value
end

return read
