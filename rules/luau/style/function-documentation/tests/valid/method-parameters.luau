local Greeter = {}

--- Returns the display name to use in a greeting, defaulting to guest.
---@param self Greeter The receiving object.
---@param name? string An optional display name.
function Greeter:greet(name: string?): string
	return name or "guest"
end

return Greeter
