type Payload = { name: string }

local function adapt(engineValue: userdata): Payload
	return (engineValue :: unknown) :: Payload
end

return adapt
