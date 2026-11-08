local function ReadValue(): number
	return 42
end

local function _readAgain(): number
	return ReadValue()
end

const ReadTwice = function(): number
	return _readAgain() * 2
end

return ReadTwice
