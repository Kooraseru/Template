local function attach(getMetatable: () -> {})
	return setmetatable({ value = 1 }, getMetatable())
end
return attach
