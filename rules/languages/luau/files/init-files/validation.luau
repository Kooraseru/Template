-- rules/languages/luau/files/init-files/validation.luau
--!strict

local Diagnostic = require("@ruleLinter/diagnostic")
local Rule = require("@ruleLinter/rule")
local Parser = require("@std/syntax/parser")
local Syntax = require("@std/syntax")

local function isChildRequire(expression: Syntax.CstExpr): boolean
	if expression.tag ~= "call" or #expression.arguments ~= 1 then
		return false
	end
	local callee = expression.func
	if callee.tag ~= "global" or callee.name.text ~= "require" then
		return false
	end
	local target = expression.arguments[1]
	if target.tag ~= "string" or (target.quoteStyle ~= "single" and target.quoteStyle ~= "double") then
		return false
	end
	local name = target.value.text:gsub("^['\"]", ""):gsub("['\"]$", "")
	local child = name:match("^@self/(.+)$") or name:match("^%./(.+)$")
	return child ~= nil and not child:find("\\", 1, true) and not ("/" .. child .. "/"):find("/../", 1, true)
end

local function placeholderIssue(expression: Syntax.CstExpr): string?
	if isChildRequire(expression) then
		return "This directory head only forwards a child module. Give it a contract or expose the child directly."
	end
	if expression.tag ~= "table" then
		return nil
	end
	if #expression.entries == 0 then
		return "This directory head returns an empty table. Give it a contract or remove the placeholder."
	end
	for _, entry in expression.entries do
		if entry.kind ~= "record" or not isChildRequire(entry.value) then
			return nil
		end
	end
	return "This directory head only lists child modules. Give the directory an owning contract."
end

return Rule.new(function(context: Rule.Context): { Diagnostic.Finding }
	local path = context.path:gsub("\\", "/")
	if path ~= "init.luau" and not path:match("/init%.luau$") then
		return {}
	end
	local parsed, block = pcall(Parser.parseBlock, context.source)
	if not parsed or #block.statements < 1 or #block.statements > 2 then
		return {}
	end
	local statement = block.statements[#block.statements]
	if statement.tag ~= "return" or #statement.expressions ~= 1 then
		return {}
	end
	local result = statement.expressions[1]
	local start = statement.location
	local issue: string?
	if #block.statements == 1 then
		issue = placeholderIssue(result)
	else
		local binding = block.statements[1]
		if (binding.tag == "local" or binding.tag == "const") and #binding.variables == 1 and #binding.values == 1
			and result.tag == "local" and result["local"] == binding.variables[1] and isChildRequire(binding.values[1]) then
			start = binding.location
			issue = "This directory head only forwards a child module. Give it a contract or expose the child directly."
		end
	end
	if not issue then
		return {}
	end
	local span = statement.location
	return {{
		line = start.beginLine, column = start.beginColumn,
		endLine = span.endLine, endColumn = span.endColumn,
		severity = "warning", message = issue,
	}}
end)
