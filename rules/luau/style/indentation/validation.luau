-- rules/luau/style/indentation/validation.luau
--!strict

local Diagnostic = require("@ruleLinter/diagnostic")
local Parser = require("@std/syntax/parser")
local Rule = require("@ruleLinter/rule")
local Syntax = require("@std/syntax")
local Visitor = require("@std/syntax/visitor")

return Rule.new(function(context: Rule.Context): { Diagnostic.Finding }
	local parsed, block = pcall(Parser.parseBlock, context.source)
	if not parsed then return {} end

	local lines = context.source:split("\n")
	local findings: { Diagnostic.Finding } = {}
	local visitor = Visitor.create()
	visitor.visitToken = function(token: Syntax.CstToken): boolean
		local span = token.location
		local prefix = lines[span.beginLine]:sub(1, span.beginColumn - 1)
		if prefix:match("^[ \t]+$") and prefix:find(" ", 1, true) then
			findings[#findings + 1] = {
				line = span.beginLine, column = 1, endLine = span.beginLine, endColumn = span.beginColumn,
				severity = "warning", message = "Use literal tabs for code indentation.",
			}
		end
		return true
	end
	Visitor.visitBlock(block, visitor)
	return findings
end)
