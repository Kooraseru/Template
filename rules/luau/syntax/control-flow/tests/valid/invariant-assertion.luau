local function requireValue(value: string?): string
	assert(value, "A value must already have been initialized")
	return value
end

return requireValue
