--[=[
Documents a Moonwave-style API.

@param name string -- Name to greet.
]=]
local function greet(name: string): string
	return name
end

return greet("-- @param example string")
