-- rules/luau/style/blank-lines/validation.luau
--!strict

local Diagnostic = require("@ruleLinter/diagnostic")
local Parser = require("@std/syntax/parser")
local PhaseLayout = require("@ruleLinter/phaseLayout")
local Rule = require("@ruleLinter/rule")
local Syntax = require("@std/syntax")
local Visitor = require("@std/syntax/visitor")

local function isNamedFunction(statement: Syntax.CstStat): boolean
	return statement.tag == "function" or statement.tag == "localfunction"
end

return Rule.new(function(context: Rule.Context): { Diagnostic.Finding }
	local parsed, block = pcall(Parser.parseBlock, context.source)
	if not parsed then
		return {}
	end

	local findings: { Diagnostic.Finding } = {}
	local visitor = Visitor.create()
	visitor.visitStatBlock = function(scope: Syntax.CstStatBlock): boolean
		local pending: { { span: Syntax.Span, standalone: boolean } } = {}

		local function finishRun()
			for _, boundary in pending do
				if #pending >= 2 or boundary.standalone then
					local span = boundary.span
					findings[#findings + 1] = {
						line = span.beginLine,
						column = span.beginColumn,
						endLine = span.endLine,
						endColumn = span.endColumn,
						severity = "warning",
						message = "Separate this statement from the preceding block with a blank line.",
					}
				end
			end
			table.clear(pending)
		end

		for index = 2, #scope.statements do
			local before, after = scope.statements[index - 1], scope.statements[index]
			local previous, current = before.location, after.location
			if current.beginLine > previous.endLine + 1 then
				finishRun()
				continue
			end
			local moduleBoundary = scope == block and (
				(previous.beginLine < previous.endLine and current.beginLine < current.endLine)
				or (isNamedFunction(before) and isNamedFunction(after))
			)
			local beforeBlock, afterBlock = PhaseLayout.IsStructured(before), PhaseLayout.IsStructured(after)
			local phaseBoundary = not PhaseLayout.IsShortExit(after) and (beforeBlock or afterBlock)
			if moduleBoundary or phaseBoundary then
				pending[#pending + 1] = { span = current, standalone = moduleBoundary or (beforeBlock and afterBlock) }
			end
		end
		finishRun()
		return true
	end
	Visitor.visitBlock(block, visitor)
	return findings
end)
