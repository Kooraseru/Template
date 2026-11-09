-- rules/luau/style/const-bindings/validation.luau
--!strict

local Diagnostic = require("@ruleLinter/diagnostic")
local Rule = require("@ruleLinter/rule")
local Parser = require("@std/syntax/parser")
local Syntax = require("@std/syntax")
local Visitor = require("@std/syntax/visitor")

return Rule.new(function(context: Rule.Context): { Diagnostic.Finding }
	local parsed, block = pcall(Parser.parseBlock, context.source)
	if not parsed then
		return {}
	end

	local candidates: { Syntax.CstStatLocal } = {}
	local exported: { [Syntax.CstLocal]: boolean } = {}
	for _, statement in block.statements do
		if statement.tag == "local" and #statement.variables == 1 and #statement.values == 1
			and statement.variables[1].name.text ~= "_" then
			table.insert(candidates, statement)
		elseif statement.tag == "return" then
			for _, value in statement.expressions do
				if value.tag == "local" then
					exported[value["local"]] = true
				end
			end
		end
	end

	local writes: { [Syntax.CstLocal]: boolean } = {}
	local visitor = Visitor.create()

	--- Track writes by lexical binding so closure writes count and shadows stay independent.
	local function recordWrite(target: Syntax.CstExpr): ()
		if target.tag == "local" then
			writes[target["local"]] = true
		end
	end

	visitor.visitStat = function(statement: Syntax.CstStat): boolean
		if statement.tag == "assign" then
			for _, target in statement.variables do
				recordWrite(target)
			end
		elseif statement.tag == "compoundassign" then
			recordWrite(statement.variable)
		end
		return true
	end
	Visitor.visitBlock(block, visitor)

	local findings: { Diagnostic.Finding } = {}
	for _, declaration in candidates do
		local binding = declaration.variables[1]
		local isModuleTable = exported[binding] and declaration.values[1].tag == "table"
		if not writes[binding] and not isModuleTable then
			local span = declaration.localKeyword.location
			findings[#findings + 1] = {
				line = span.beginLine, column = span.beginColumn,
				endLine = span.endLine, endColumn = span.endColumn,
				severity = "information", message = "This binding is never reassigned and can use const.",
			}
		end
	end
	return findings
end)
