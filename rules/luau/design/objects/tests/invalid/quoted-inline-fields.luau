local Widget = {}
function Widget.new(name: string)
	return setmetatable({ ["display-name"] = name }, Widget)
end
return Widget
