type EngineValue = { name: unknown }

type Payload = { name: string }

local function adapt(engineValue: EngineValue): Payload
	return (engineValue :: unknown) :: Payload
end

return adapt
