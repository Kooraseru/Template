-- global-rules/languages/luau/declarative-data/tests/valid/table-operations.luau
--!strict

const values: { string } = {}

local function Replace(value: string): ()
	table.insert(values, value)
	table.remove(values, 1)
	table.clear(values)
end

return Replace
