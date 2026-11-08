-- rules/luau/style/function-documentation/validation.luau
--!strict

local Diagnostic = require("@ruleLinter/diagnostic")
local Rule = require("@ruleLinter/rule")
local Comments = require("@ruleLinter/comments")
local Parser = require("@std/syntax/parser")
local Query = require("@std/syntax/query")
local Syntax = require("@std/syntax")
local Utils = require("@std/syntax/utils")

local function annotationIssue(text: string): string?
	local tag, body = text:match("^%-%-%-?%s*@([%a]+)%s*(.*)$")
	if not tag then
		return nil
	end
	if tag ~= "param" and tag ~= "return" and tag ~= "generic" and tag ~= "class" and tag ~= "field" and tag ~= "type" and tag ~= "enum" then
		return nil
	end
	if not text:match("^%-%-%-") then
		return "Start a LuaCATS @" .. tag .. " annotation with three dashes."
	end
	if not body or body == "" or (tag == "param" and not body:match("^%S+%s+%S")) then
		return "Complete the LuaCATS @" .. tag .. " annotation or remove it."
	end
	return nil
end

return Rule.new(function(context: Rule.Context): { Diagnostic.Finding }
	local findings: { Diagnostic.Finding } = {}
	local lines = context.source:split("\n")
	local docLines: { [number]: { text: string, span: Syntax.Span } } = {}
	local function report(span: Syntax.Span, message: string)
		findings[#findings + 1] = {
			line = span.beginLine, column = span.beginColumn,
			endLine = span.endLine, endColumn = span.endColumn,
			severity = "warning", message = message,
		}
	end
	Comments.VisitLineComments(context.source, function(comment, span)
		local issue = annotationIssue(comment)
		if issue then
			report(span, issue)
		end
		if comment:match("^%-%-%-") and lines[span.beginLine]:sub(1, span.beginColumn - 1):match("^%s*$") then
			docLines[span.beginLine] = { text = comment, span = span }
		end
	end)
	local parsed, block = pcall(Parser.parseBlock, context.source)
	if not parsed then
		return findings
	end
	local function checkFunctionDocs(func: Syntax.CstExprFunction, declarationLine: number)
		local names: { [string]: boolean } = {}
		for _, parameter in func.parameters do
			names[parameter.name.text] = true
		end
		if func.self then
			names.self = true
		end
		local line = declarationLine - 1
		while docLines[line] do
			local doc = docLines[line]
			local name = doc.text:match("^%-%-%-%s*@param%s+([%a_][%w_]*)%??%s+%S")
			if name and not names[name] then
				report(doc.span, "LuaCATS documents a parameter absent from this declaration: " .. name .. ".")
			end
			local tag = doc.text:match("^%-%-%-%s*@([%a_]+)%f[^%w_]")
			if tag == "readonly" then
				report(doc.span, "Reserve @readonly for property documentation.")
			elseif tag == "function" or tag == "method" then
				report(doc.span, "Remove this declaration tag from a function already declared in Luau.")
			end
			line -= 1
		end
	end
	for _, declaration in Query.findAllFromRoot(block, Utils.isStatLocalFunction).nodes do
		checkFunctionDocs(declaration.func, declaration.location.beginLine)
	end
	for _, declaration in Query.findAllFromRoot(block, Utils.isStatFunction).nodes do
		checkFunctionDocs(declaration.func, declaration.location.beginLine)
	end
	return findings
end)
