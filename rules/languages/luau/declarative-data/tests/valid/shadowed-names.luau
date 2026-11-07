-- global-rules/languages/luau/declarative-data/tests/valid/shadowed-names.luau
--!strict

local function Build(): { [string]: boolean }
	const colors = {}
	for _, color in { "red", "blue" } do
		colors[color] = true
	end
	return colors
end

return Build
