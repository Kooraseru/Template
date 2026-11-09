-- rules/luau/syntax/types/validation.luau
--!strict

local Rule = require("@ruleLinter/rule")
local Diagnostic = require("@ruleLinter/diagnostic")
local Parser = require("@std/syntax/parser")
local Query = require("@std/syntax/query")
local Syntax = require("@std/syntax")
local Utils = require("@std/syntax/utils")

local function sourceAt(lines: { string }, span: Syntax.Span): string
	if span.beginLine == span.endLine then
		return lines[span.beginLine]:sub(span.beginColumn, span.endColumn - 1)
	end
	local parts = { lines[span.beginLine]:sub(span.beginColumn) }
	for line = span.beginLine + 1, span.endLine - 1 do
		parts[#parts + 1] = lines[line]
	end
	parts[#parts + 1] = lines[span.endLine]:sub(1, span.endColumn - 1)
	return table.concat(parts, "\n")
end

local function sameAnnotation(lines: { string }, inner: Syntax.CstType, outer: Syntax.CstType): boolean
	if inner.tag == "reference" and outer.tag == "reference" and not inner.openParameters and not outer.openParameters then
		local innerPrefix = if inner.prefix then inner.prefix.text else nil
		local outerPrefix = if outer.prefix then outer.prefix.text else nil
		return inner.name.text == outer.name.text and innerPrefix == outerPrefix
	end
	return inner.tag == outer.tag and sourceAt(lines, inner.location) == sourceAt(lines, outer.location)
end

return Rule.new(function(context: Rule.Context): { Diagnostic.Finding }
	local parsed, ast = pcall(Parser.parseBlock, context.source)
	if not parsed then
		return {}
	end
	local findings: { Diagnostic.Finding } = {}
	local lines = context.source:split("\n")

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
		if outer.tag == "reference" and not outer.prefix and outer.name.text == "any" then
			continue
		end
		local operand = assertion.operand
		while operand.tag == "group" do
			operand = operand.expression
		end
		if operand.tag ~= "cast" then
			continue
		end
		if not sameAnnotation(lines, operand.annotation, outer) then
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
