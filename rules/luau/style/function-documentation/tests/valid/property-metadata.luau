---@readonly
local defaultName = "guest"

--- Read the default name for an anonymous guest.
---@deprecated 2.0
local function greet(): string
	return defaultName
end

return greet
