local function readValue(): number
	return 42
end

local Reader = {}
local readTwice = function(): number
	return readValue() * 2
end

function Reader.Read(): number
	return readTwice()
end
return Reader
