type Box<T> = { value: T }
local function inspect(item: Box<number>)
	return (item :: Box<number>) :: Box<number | string>
end
return inspect
