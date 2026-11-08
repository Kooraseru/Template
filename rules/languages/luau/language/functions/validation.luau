-- rules/languages/luau/language/functions/validation.luau
--!strict

local Diagnostic = require("@ruleLinter/diagnostic")
local Parser = require("@std/syntax/parser")
local Query = require("@std/syntax/query")
local Rule = require("@ruleLinter/rule")
local Utils = require("@std/syntax/utils")

return Rule.new(function(context: Rule.Context): { Diagnostic.Finding }
	local parsed, block = pcall(Parser.parseBlock, context.source)
	if not parsed then
		return {}
	end
	local last = block.statements[#block.statements]
	if not last or last.tag ~= "return" or #last.expressions == 0 then
		return {}
	end
	local findings: { Diagnostic.Finding } = {}
	for _, statement in Query.findAllFromRoot(block, Utils.isStatFunction).nodes do
		local name = statement.name
		if name.tag ~= "global" then
			continue
		end
		local span = name.location
		findings[#findings + 1] = {
			line = span.beginLine, column = span.beginColumn,
			endLine = span.endLine, endColumn = span.endColumn,
			severity = "warning", message = "A bare function declaration in a returning module writes a global. Declare a local helper or a method on the module surface.",
		}
	end
	return findings
end)
