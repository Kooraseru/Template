local Widget = {}
function Widget.new(name: string)
	return setmetatable({ [resolveKey()] = name }, Widget)
end
return Widget
