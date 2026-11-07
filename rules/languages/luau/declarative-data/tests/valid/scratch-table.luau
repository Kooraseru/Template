-- global-rules/languages/luau/declarative-data/tests/valid/scratch-table.luau
--!strict

local function Unique(values: { string }): { [string]: boolean }
	const seen = {}
	for _, value in values do
		seen[value] = true
	end
	return seen
end

return Unique
