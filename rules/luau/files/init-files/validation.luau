-- rules/luau/files/init-files/validation.luau
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

local function placeholderIssue(expression: Syntax.CstExpr, isForward: (Syntax.CstExpr) -> boolean, hasBindings: boolean): string?
	if isForward(expression) then
		return "This directory head only forwards a child module. Give it a contract or expose the child directly."
	end
	if expression.tag ~= "table" then
		return nil
	end
	if #expression.entries == 0 then
		return if hasBindings then nil else "This directory head returns an empty table. Give it a contract or remove the placeholder."
	end
	for _, entry in expression.entries do
		if entry.kind ~= "record" or not isForward(entry.value) then
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
	if not parsed or #block.statements < 1 then
		return {}
	end
	local statement = block.statements[#block.statements]
	if statement.tag ~= "return" or #statement.expressions ~= 1 then
		return {}
	end
	local forwarded: { [Syntax.CstLocal]: boolean } = {}
	for index = 1, #block.statements - 1 do
		local declaration = block.statements[index]
		if (declaration.tag ~= "local" and declaration.tag ~= "const")
			or #declaration.variables ~= #declaration.values then
			return {}
		end
		for slot, binding in declaration.variables do
			if not isChildRequire(declaration.values[slot]) then
				return {}
			end
			forwarded[binding] = false
		end
	end

	local function isForward(expression: Syntax.CstExpr): boolean
		if expression.tag == "local" and forwarded[expression["local"]] ~= nil then
			forwarded[expression["local"]] = true
			return true
		end
		return isChildRequire(expression)
	end

	local issue = placeholderIssue(statement.expressions[1], isForward, #block.statements > 1)
	if not issue then
		return {}
	end

	for _, used in forwarded do
		if not used then
			return {}
		end
	end

	local start = block.statements[1].location
	local span = statement.location
	return {{
		line = start.beginLine, column = start.beginColumn,
		endLine = span.endLine, endColumn = span.endColumn,
		severity = "warning", message = issue,
	}}
end)
