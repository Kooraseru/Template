local Clamp = {}
function Clamp.Clamp(value: number): number
	return if value < 0 then Clamp.Clamp(-value) else math.min(value, 1)
end
return Clamp
