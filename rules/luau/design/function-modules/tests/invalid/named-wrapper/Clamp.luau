local Clamp = {}
function Clamp.Clamp(value: number): number
	return math.clamp(value, 0, 1)
end
return Clamp
