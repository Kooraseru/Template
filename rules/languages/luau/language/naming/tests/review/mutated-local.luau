local RETRY_LIMIT = 10_000

local function update()
	RETRY_LIMIT -= 1
	return RETRY_LIMIT
end

return update
