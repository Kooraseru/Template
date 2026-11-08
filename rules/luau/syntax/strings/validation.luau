-- rules/luau/syntax/strings/validation.luau
--!strict

local Diagnostic = require("@ruleLinter/diagnostic")
local Rule = require("@ruleLinter/rule")
local Parser = require("@std/syntax/parser")
local Syntax = require("@std/syntax")
local Query = require("@std/syntax/query")
local Utils = require("@std/syntax/utils")

local function isQuotedLiteral(node: Syntax.CstExpr): boolean
	return node.tag == "string" and (node.quoteStyle == "single" or node.quoteStyle == "double")
end

local function replacesTostring(block: Syntax.CstStatBlock): boolean
	for _, assignment in Query.findAllFromRoot(block, Utils.isStatAssign).nodes do
		for _, target in assignment.variables do
			if target.tag == "global" and target.name.text == "tostring" then
				return true
			end
		end
	end
	for _, declaration in Query.findAllFromRoot(block, Utils.isStatFunction).nodes do
		if declaration.name.tag == "global" and declaration.name.name.text == "tostring" then
			return true
		end
	end
	return false
end

local function isRedundantTostring(expression: Syntax.CstExpr): boolean
	if expression.tag ~= "call" or #expression.arguments ~= 1 then
		return false
	end
	local callee = expression.func
	if callee.tag ~= "global" or callee.name.text ~= "tostring" then
		return false
	end
	local value = expression.arguments[1]
	return value.tag == "local" or value.tag == "boolean" or value.tag == "number"
		or value.tag == "integer" or value.tag == "nil" or isQuotedLiteral(value)
end

return Rule.new(function(context: Rule.Context): { Diagnostic.Finding }
	local parsed, block = pcall(Parser.parseBlock, context.source)
	if not parsed then
		return {}
	end
	local findings: { Diagnostic.Finding } = {}
	local function report(span: Syntax.Span, message: string)
		findings[#findings + 1] = {
			line = span.beginLine, column = span.beginColumn,
			endLine = span.endLine, endColumn = span.endColumn,
			severity = "warning", message = message,
		}
	end
	for _, node in Query.findAllFromRoot(block, Utils.isExprBinary).nodes do
		local left = node.lhsOperand
		local right = node.rhsOperand
		if node.operator.text ~= ".." or node.location.beginLine ~= node.location.endLine then
			continue
		end
		local leftQuoted = isQuotedLiteral(left)
		local rightQuoted = isQuotedLiteral(right)
		if leftQuoted and rightQuoted then
			report(node.location, "Use one quoted literal for constant text.")
		elseif (leftQuoted and right.tag == "interpolatedstring") or (rightQuoted and left.tag == "interpolatedstring") then
			report(node.location, "Include the literal text inside the interpolated string.")
		end
	end
	local builtinTostring = not replacesTostring(block)
	for _, node in Query.findAllFromRoot(block, Utils.isExprInterpString).nodes do
		for _, expression in node.expressions do
			if isQuotedLiteral(expression) then
				report(expression.location, "Write this constant text directly in the interpolated string.")
			elseif builtinTostring and #node.expressions == 1 and isRedundantTostring(expression) then
				report(expression.location, "Interpolation already converts this value to text. Remove the redundant tostring call.")
			end
		end
	end
	for _, call in Query.findAllFromRoot(block, Utils.isExprCall).nodes do
		local callee = call.func
		if callee.tag ~= "indexname" or callee.accessor.text ~= "." or callee.index.text ~= "format" or #call.arguments ~= 2 then
			continue
		end
		local library = callee.expression
		local pattern, value = call.arguments[1], call.arguments[2]
		if library.tag ~= "global" or library.name.text ~= "string" or pattern.tag ~= "string"
			or value.tag ~= "string" or not isQuotedLiteral(value) then
			continue
		end
		if value.value.text:find("\\", 1, true) or value.value.text:find("\0", 1, true) then
			continue
		end
		local text = pattern.value.text
		if text == "%s" and isQuotedLiteral(pattern) then
			report(call.location, "Use the quoted string directly when %s adds no formatting.")
		end
	end
	return findings
end)
