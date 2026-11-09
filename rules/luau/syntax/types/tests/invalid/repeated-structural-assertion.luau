type Box<T> = { value: T }
local function inspect(item: Box<number>, input: { value: number })
	local record = (item :: Box<number>) :: Box<number>
	local copy = (input :: {
		value: number,
	}) :: {
		value: number,
	}
	return record, copy
end
return inspect
