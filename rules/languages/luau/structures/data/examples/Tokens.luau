-- structures/data: Tokens.luau
--!strict

type RGB = {
	red: number,
	green: number,
	blue: number,
}

local text: RGB = { red = 235, green = 235, blue = 235 }
local panel: RGB = { red = 24, green = 26, blue = 30 }

return {
	spacing = {
		small = 4,
		medium = 8,
		large = 12,
	},

	color = {
		text = text,
		panel = panel,
	},
}
