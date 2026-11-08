--!strict

local Diagnostic = require("@ruleLinter/diagnostic")
local Parser = require("@std/syntax/parser")
local Rule = require("@ruleLinter/rule")

return Rule.new(function(context: Rule.Context): { Diagnostic.Finding }
	local parsed, block = pcall(Parser.parseBlock, context.source)
	if not parsed then
		return {}
	end

	local findings: { Diagnostic.Finding } = {}
	for index = 2, #block.statements do
		local previous = block.statements[index - 1].location
		local current = block.statements[index].location
		local areAdjacent = current.beginLine == previous.endLine + 1
		local areBothMultiLine = previous.beginLine < previous.endLine and current.beginLine < current.endLine
		if areAdjacent and areBothMultiLine then
			findings[#findings + 1] = {
				line = current.beginLine,
				column = current.beginColumn,
				endLine = current.endLine,
				endColumn = current.endColumn,
				severity = "warning",
				message = "Separate adjacent multi-line module statements with a blank line.",
			}
		end
	end
	return findings
end)
