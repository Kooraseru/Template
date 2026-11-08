-- rules/luau/files/module-roots/validation.luau
--!strict

local Diagnostic = require("@ruleLinter/diagnostic")
local Rule = require("@ruleLinter/rule")

return Rule.new(function(context: Rule.Context): { Diagnostic.Finding }
	local path = context.path:gsub("\\", "/")
	if path ~= "index.luau" and not path:match("/index%.luau$") then
		return {}
	end

	local first = context.source:match("^[^\r\n]*") or ""
	return {{
		line = 1, column = 1, endLine = 1, endColumn = #first + 1,
		severity = "information",
		message = "Confirm this index.luau has an explicit resolver convention, or use init.luau for a directory head.",
	}}
end)
