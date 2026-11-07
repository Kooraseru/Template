-- global-rules/languages/luau/structures/functional/examples/Clamp.luau
--!strict

return function(value: number, minimum: number, maximum: number): number
	return math.clamp(value, minimum, maximum)
end
