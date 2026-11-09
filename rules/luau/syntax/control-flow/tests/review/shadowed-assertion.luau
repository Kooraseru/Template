local function assert(value: string?): string
	return value or "fallback"
end

local ok, result = pcall(assert, nil)
return ok, result
