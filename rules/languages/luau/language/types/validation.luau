-- rules/languages/luau/language/types/validation.luau
--!strict

local Rule = require("@ruleLinter/rule")
local Diagnostic = require("@ruleLinter/diagnostic")
local Parser = require("@std/syntax/parser")
local Query = require("@std/syntax/query")
local Utils = require("@std/syntax/utils")

return Rule.new(function(context: Rule.Context): { Diagnostic.Finding }
	local parsed, ast = pcall(Parser.parseBlock, context.source)
	if not parsed then
		return {}
	end
	local findings: { Diagnostic.Finding } = {}
	for _, reference in Query.findAllFromRoot(ast, Utils.isTypeReference).nodes do
		if reference.prefix ~= nil or reference.name.text ~= "any" then
			continue
		end
		local span = reference.name.location
		findings[#findings + 1] = {
			line = span.beginLine, column = span.beginColumn,
			endLine = span.endLine, endColumn = span.endColumn,
			severity = "error", message = "Use unknown or an explicit type instead of any in Luau annotations.",
		}
	end
	return findings
end)
