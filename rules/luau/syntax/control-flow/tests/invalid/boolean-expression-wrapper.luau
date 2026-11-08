local function inspect(a: number, b: number, ready: boolean?): (boolean, boolean, boolean)
	local grouped = if (a < b) then true else false
	local negated = if not ready then true else false
	local compound = if a < b and (b == 0 or not ready) then true else false
	return grouped, negated, compound
end
return inspect
