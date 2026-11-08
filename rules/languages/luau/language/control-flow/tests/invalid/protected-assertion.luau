local function isReady(value: string?): boolean
	local ready = pcall(assert, value, "Expected a value")
	return ready
end

return isReady
