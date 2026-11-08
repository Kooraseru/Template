local function selectDefaults(includeAll: boolean): { number }
	local defaults = {
		1,
		2,
		3,
		4,
		5,
		6,
		7,
		8,
		9,
		10,
		11,
		12,
		13,
		14,
		15,
		16,
		17,
		18,
		19,
		20,
		21,
		22,
		23,
		24,
	}
	if includeAll then
		return defaults
	end
	local selected = {}
	for index, value in defaults do
		if index % 2 == 0 then
			selected[#selected + 1] = value
		end
	end
	return selected
end

return selectDefaults
