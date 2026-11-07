-- rules/languages/luau/language/function-documentation/validation.luau
--!strict

local Diagnostic = require("@ruleLinter/diagnostic")
local Rule = require("@ruleLinter/rule")
local Parser = require("@std/syntax/parser")
local Syntax = require("@std/syntax")
local Visitor = require("@std/syntax/visitor")

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
	local parsed, file = pcall(Parser.parse, context.source)
	if not parsed then
		return {}
	end
	local findings: { Diagnostic.Finding } = {}
	local seen: { [string]: boolean } = {}
	local function checkTrivia(trivia: Syntax.Trivia)
		if trivia.tag ~= "comment" then
			return
		end
		local issue = annotationIssue(trivia.text)
		if not issue then
			return
		end
		local span = trivia.location
		local key = `{span.beginLine}:{span.beginColumn}`
		if seen[key] then
			return
		end
		seen[key] = true
		findings[#findings + 1] = {
			line = span.beginLine, column = span.beginColumn,
			endLine = span.endLine, endColumn = span.endColumn,
			severity = "warning", message = issue,
		}
	end
	local function checkToken(token: Syntax.CstToken): boolean
		for _, trivia in token.leadingTrivia do
			checkTrivia(trivia)
		end
		for _, trivia in token.trailingTrivia do
			checkTrivia(trivia)
		end
		return true
	end
	local visitor = Visitor.create()
	visitor.visitToken = checkToken
	Visitor.visitBlock(file.root, visitor)
	checkToken(file.eof)
	return findings
end)
