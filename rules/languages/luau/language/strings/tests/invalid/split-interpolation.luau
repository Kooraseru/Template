local function describe(name: string): (string, string, string)
	return "Hello " .. `{name}`, `{name}` .. "!", `Hello {"world"}`
end

return describe
