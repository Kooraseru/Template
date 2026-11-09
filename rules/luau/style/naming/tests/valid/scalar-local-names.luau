local userName = "guest"
local function count(): number
	local retryCount = 0
	retryCount += 1
	return retryCount
end
return userName, count
