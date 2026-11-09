-- rules/luau/files/path-headers/validation.luau
--!strict

local Rule = require("@ruleLinter/rule")
local Diagnostic = require("@ruleLinter/diagnostic")

return Rule.new(function(context: Rule.Context): { Diagnostic.Finding }
	local path = context.path:gsub("\\", "/")
	if not path:match("%.luau$") or not (
		path:match("^source/") or path:match("^%.github/ci/") or path:match("^dependencies/packages/")
	) then
		return {}
	end

	for segment in path:gmatch("[^/]+") do
		if segment == "vendor" or segment == "generated" or segment == "examples" or segment == "tests" or segment == "node_modules" or segment == "build" then
			return {}
		end
	end

	local expected = "-- " .. path
	local first = context.source:match("^[^\r\n]*")
	if first == expected then
		return {}
	end
	return {{
		line = 1, column = 1, endLine = 1, endColumn = if first and first:match("^%-%- .+%.luau$") then #first + 1 else 1,
		severity = "error", message = "Expected path header: " .. expected,
	}}
end)
