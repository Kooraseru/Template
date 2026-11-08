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
	for _, assertion in Query.findAllFromRoot(ast, Utils.isExprTypeAssertion).nodes do
		local outer = assertion.annotation
		if outer.tag ~= "reference" or outer.openParameters or (not outer.prefix and outer.name.text == "any") then
			continue
		end
		local operand = assertion.operand
		while operand.tag == "group" do
			operand = operand.expression
		end
		if operand.tag ~= "cast" then
			continue
		end
		local inner = operand.annotation
		if inner.tag ~= "reference" or inner.openParameters or inner.name.text ~= outer.name.text then
			continue
		end
		local innerPrefix = if inner.prefix then inner.prefix.text else nil
		local outerPrefix = if outer.prefix then outer.prefix.text else nil
		if innerPrefix ~= outerPrefix then
			continue
		end
		local start = assertion.operator.location
		local finish = outer.location
		findings[#findings + 1] = {
			line = start.beginLine, column = start.beginColumn,
			endLine = finish.endLine, endColumn = finish.endColumn,
			severity = "warning", message = "Remove the repeated Luau type assertion.",
		}
	end
	return findings
end)
