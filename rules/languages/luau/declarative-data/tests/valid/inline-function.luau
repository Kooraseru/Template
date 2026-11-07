-- global-rules/languages/luau/declarative-data/tests/valid/inline-function.luau
--!strict

const Handler = {
	Run = function(value: string): string
		return value:lower()
	end,
}

return Handler
