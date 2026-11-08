local function resolveKey(): string
	return "runtimeKey"
end

local Widget = {}
function Widget.new(name: string)
	return setmetatable({ [resolveKey()] = name }, Widget)
end
return Widget
