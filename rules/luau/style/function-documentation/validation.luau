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
	local blockDocs: { [number]: Syntax.Span } = {}
	local function reportRange(line: number, column: number, endLine: number, endColumn: number, message: string)
		findings[#findings + 1] = {
			line = line, column = column, endLine = endLine, endColumn = endColumn,
			severity = "warning", message = message,
		}
	end
	local function report(span: Syntax.Span, message: string)
		reportRange(span.beginLine, span.beginColumn, span.endLine, span.endColumn, message)
	end
	local parsed, file = pcall(Parser.parse, context.source)
	if not parsed then
		return findings
	end
	Comments.VisitComments(file, function(comment, span, block)
		if block then
			if lines[span.beginLine]:sub(1, span.beginColumn - 1):match("^%s*$")
				and lines[span.endLine]:sub(span.endColumn):match("^%s*$") then
				blockDocs[span.endLine] = span
			end
			return
		end
		local issue = annotationIssue(comment)
		if issue then
			report(span, issue)
		end
		if comment:match("^%-%-%-") and lines[span.beginLine]:sub(1, span.beginColumn - 1):match("^%s*$") then
			docLines[span.beginLine] = { text = comment, span = span }
		end
	end)
	local function checkBlockSpacing(declarationLine: number)
		local span = blockDocs[declarationLine - 1]
		if not span then
			return
		end
		local hasProse, fenced = false, false
		for line = span.beginLine + 1, span.endLine - 1 do
			local content = lines[line]:match("^%s*(.-)%s*$") or ""
			if content:match("^```") then
				fenced = not fenced
			elseif not fenced and (content:match("^@param%s") or content:match("^@return%s")) then
				if hasProse and not lines[line - 1]:match("^%s*$") then
					local column = #(lines[line]:match("^%s*") or "") + 1
					reportRange(line, column, line, column + #content,
						"Leave a blank line between Moonwave prose and its annotation tags.")
				end
				break
			elseif not fenced and content ~= "" and not content:match("^@") then
				hasProse = true
			end
		end
	end
	local function checkFunctionDocs(func: Syntax.CstExprFunction, declarationLine: number)
		checkBlockSpacing(declarationLine)
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
	for _, declaration in Query.findAllFromRoot(file.root, Utils.isStatLocalFunction).nodes do
		checkFunctionDocs(declaration.func, declaration.location.beginLine)
	end
	for _, declaration in Query.findAllFromRoot(file.root, Utils.isStatFunction).nodes do
		checkFunctionDocs(declaration.func, declaration.location.beginLine)
	end
	return findings
end)
