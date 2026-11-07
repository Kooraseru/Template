-- global-rules/languages/luau/declarative-data/tests/valid/computed-collection.luau
--!strict

local function Indices(count: number): { number }
	const result = {}
	for index = 1, count do
		table.insert(result, index * index)
	end
	return result
end

return Indices
