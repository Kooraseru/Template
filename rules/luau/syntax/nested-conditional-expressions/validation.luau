-- rules/luau/syntax/nested-conditional-expressions/validation.luau
--!strict

local Diagnostic = require("@ruleLinter/diagnostic")
local Parser = require("@std/syntax/parser")
local Rule = require("@ruleLinter/rule")
local Syntax = require("@std/syntax")
local Visitor = require("@std/syntax/visitor")

local function isConditional(expression: Syntax.CstExpr): boolean
	while expression.tag == "group" do
		expression = expression.expression
	end
	return expression.tag == "conditional"
end

return Rule.new(function(context: Rule.Context): { Diagnostic.Finding }
	local parsed, block = pcall(Parser.parseBlock, context.source)
	if not parsed then return {} end

	local findings: { Diagnostic.Finding } = {}
	local visitor = Visitor.create()
	visitor.visitExprIfElse = function(expression: Syntax.CstExprIfElse): boolean
		local nested = isConditional(expression.condition) or isConditional(expression.thenExpr) or isConditional(expression.elseExpr)
		for _, branch in expression.elseifs do
			nested = nested or isConditional(branch.condition) or isConditional(branch.thenExpr)
		end
		if nested then
			local span = expression.location
			findings[#findings + 1] = {
				line = span.beginLine, column = span.beginColumn, endLine = span.endLine, endColumn = span.endColumn,
				severity = "warning", message = "Give the nested conditional a name or use an explicit branch.",
			}
		end
		return true
	end
	Visitor.visitBlock(block, visitor)
	return findings
end)
