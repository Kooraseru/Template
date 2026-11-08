local function copyPositive(entries: { number }): { number }
	local result = {}
	for _, entry in entries do
		if entry > 0 then
			result[#result + 1] = entry
		end
	end
	return result
end

return copyPositive
