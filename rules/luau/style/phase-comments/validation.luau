-- rules/luau/style/phase-comments/validation.luau
--!strict

local Comments = require("@ruleLinter/comments")
local Diagnostic = require("@ruleLinter/diagnostic")
local Parser = require("@std/syntax/parser")
local PhaseLayout = require("@ruleLinter/phaseLayout")
local Rule = require("@ruleLinter/rule")
local Syntax = require("@std/syntax")
local Visitor = require("@std/syntax/visitor")

const MIN_STATEMENT_LINES = 12

type Comment = { span: Syntax.Span, prose: boolean }

local function hasProse(text: string, block: boolean): boolean
	local body = if block then text:gsub("^%-%-%[=*%[", ""):gsub("%]=*%]%s*$", "") else text:gsub("^%-+", "")
	for _, line in body:split("\n") do
		local content = line:match("^%s*(.-)%s*$") or ""
		if content:match("^[!#@]") or content:match("^%S+%.luau?$") then
			continue
		end
		if content:gsub("[%s%p%d]", "") ~= "" then
			return true
		end
	end
	return false
end

local function isExecutable(statement: Syntax.CstStat): boolean
	return statement.tag ~= "typealias" and statement.tag ~= "typefunction" and statement.tag ~= "block"
		and statement.tag ~= "localfunction" and statement.tag ~= "function"
end

local function hasEnoughCode(body: Syntax.CstStatBlock): boolean
	local seen: { [number]: boolean } = {}
	local count = 0
	local visitor = Visitor.create()
	visitor.visitStat = function(statement: Syntax.CstStat): boolean
		local line = statement.location.beginLine
		if isExecutable(statement) and not seen[line] then
			seen[line] = true
			count += 1
		end
		return count < MIN_STATEMENT_LINES and statement.tag ~= "typefunction"
	end
	visitor.visitExprFunction = function(): boolean
		return false
	end
	Visitor.visitBlock(body, visitor)
	return count >= MIN_STATEMENT_LINES
end

local function explained(comments: { [number]: Comment }, target: Syntax.Span): boolean
	local line = target.beginLine - 1
	while comments[line] do
		local comment = comments[line]
		if comment.span.beginColumn ~= target.beginColumn then
			break
		end
		if comment.prose then
			return true
		end
		line = comment.span.beginLine - 1
	end
	return false
end

return Rule.new(function(context: Rule.Context): { Diagnostic.Finding }
	local parsed, file = pcall(Parser.parse, context.source)
	if not parsed then
		return {}
	end

	local findings: { Diagnostic.Finding } = {}
	local lines = context.source:split("\n")
	local comments: { [number]: Comment } = {}
	Comments.VisitComments(file, function(text, span, block)
		local before = lines[span.beginLine]:sub(1, span.beginColumn - 1)
		local after = lines[span.endLine]:sub(span.endColumn)
		if before:match("^%s*$") and after:match("^%s*$") then
			comments[span.endLine] = { span = span, prose = hasProse(text, block) }
		end
	end)

	local visitor = Visitor.create()
	visitor.visitExprFunction = function(func: Syntax.CstExprFunction): boolean
		if not hasEnoughCode(func.body) then
			return true
		end
		local statements = func.body.statements
		local reported = 0
		for index = 2, #statements do
			local before, after = statements[index - 1], statements[index]
			if not isExecutable(before) or not isExecutable(after) or PhaseLayout.IsShortExit(after)
				or not (PhaseLayout.IsControlPhase(before) or PhaseLayout.IsControlPhase(after)) then
				continue
			end

			local span = after.location
			if not explained(comments, span) then
				findings[#findings + 1] = {
					line = span.beginLine, column = span.beginColumn,
					endLine = span.beginLine, endColumn = #lines[span.beginLine]:gsub("\r$", "") + 1,
					severity = "information",
					message = "Consider explaining what this phase does or what must stay true here.",
				}
				reported += 1
				if reported == 2 then
					break
				end
			end
		end
		return true
	end
	Visitor.visitBlock(file.root, visitor)
	return findings
end)
