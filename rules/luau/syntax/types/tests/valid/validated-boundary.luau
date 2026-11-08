type Payload = { name: string }

local function read(value: unknown): Payload?
	if type(value) == "table" and type(value.name) == "string" then
		return value :: Payload
	end
	return nil
end

return read
