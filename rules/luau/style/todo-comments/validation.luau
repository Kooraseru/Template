-- rules/luau/style/todo-comments/validation.luau
--!strict

local Comments = require("@ruleLinter/comments")
local Diagnostic = require("@ruleLinter/diagnostic")
local Parser = require("@std/syntax/parser")
local Rule = require("@ruleLinter/rule")

return Rule.new(function(context: Rule.Context): { Diagnostic.Finding }
	local parsed, file = pcall(Parser.parse, context.source)
	if not parsed then return {} end

	local findings: { Diagnostic.Finding } = {}
	Comments.VisitComments(file, function(text, span, block)
		local body = if block then text:gsub("^%-%-%[=*%[", ""):gsub("%]=*%]%s*$", "") else text:gsub("^%-+", "")
		if body:match("^%s*TODO[%s:!?.%-]*$") then
			findings[#findings + 1] = {
				line = span.beginLine, column = span.beginColumn, endLine = span.endLine, endColumn = span.endColumn,
				severity = "warning", message = "Describe the follow-up or remove this empty TODO.",
			}
		end
	end)
	return findings
end)
