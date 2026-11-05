-- rules/languages/luau/structures/procedural/examples/TableModule.luau
--!strict

local Text = {}

function Text.Measure(value: string): number
	return #value
end

return Text
