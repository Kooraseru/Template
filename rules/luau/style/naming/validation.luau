-- rules/luau/style/naming/validation.luau
--!strict

local Diagnostic = require("@ruleLinter/diagnostic")
local Rule = require("@ruleLinter/rule")
local Parser = require("@std/syntax/parser")
local Syntax = require("@std/syntax")
local Query = require("@std/syntax/query")
local Utils = require("@std/syntax/utils")

local function isScalarLiteral(value: Syntax.CstExpr): boolean
	while value.tag == "group" do
		value = value.expression
	end
	if value.tag == "unary" and value.operator.text == "-" then
		local operand = value.operand
		return operand.tag == "number" or operand.tag == "integer"
	end
	return value.tag == "number" or value.tag == "integer" or value.tag == "boolean"
		or (value.tag == "string" and value.quoteStyle ~= "interp")
end

return Rule.new(function(context: Rule.Context): { Diagnostic.Finding }
	local parsed, block = pcall(Parser.parseBlock, context.source)
	if not parsed then
		return {}
	end
	local findings: { Diagnostic.Finding } = {}
	local function report(span: Syntax.Span, message: string)
		findings[#findings + 1] = {
			line = span.beginLine, column = span.beginColumn,
			endLine = span.endLine, endColumn = span.endColumn,
			severity = "warning", message = message,
		}
	end
	local reassigned: { [Syntax.CstLocal]: boolean } = {}
	for _, assignment in Query.findAllFromRoot(block, Utils.isStatAssign).nodes do
		for _, target in assignment.variables do
			if target.tag == "local" then
				reassigned[target["local"]] = true
			end
		end
	end
	for _, assignment in Query.findAllFromRoot(block, Utils.isStatCompoundAssign).nodes do
		local target = assignment.variable
		if target.tag == "local" then
			reassigned[target["local"]] = true
		end
	end
	for _, alias in Query.findAllFromRoot(block, Utils.isStatTypeAlias).nodes do
		local name = alias.name
		if not name.text:match("^[A-Z][A-Za-z0-9]*$") then
			report(name.location, "Use PascalCase for Luau type aliases.")
		end
	end
	for _, declaration in Query.findAllFromRoot(block, Utils.isExprFunction).nodes do
		for _, parameter in declaration.parameters do
			local name = parameter.name
			if name.text ~= "_" and not name.text:match("^[a-z][A-Za-z0-9]*$") then
				report(name.location, "Use camelCase for Luau parameters or a bare underscore for an ignored argument.")
			end
		end
	end
	for _, declaration in Query.findAllFromRoot(block, Utils.isStatLocalFunction).nodes do
		local name = declaration.name.name
		if not name.text:match("^[a-z][A-Za-z0-9]*$") then
			report(name.location, "Use camelCase for local Luau function names.")
		end
	end
	local function checkBinding(name: Syntax.CstToken<string>): boolean
		if name.text ~= "_" and name.text:match("^_") then
			report(name.location, "Avoid an underscore prefix on a Luau binding.")
			return false
		end
		return name.text ~= "_"
	end
	for _, declaration in Query.findAllFromRoot(block, Utils.isStatLocal).nodes do
		for index, variable in declaration.variables do
			local name = variable.name
			local value = declaration.values[index]
			if not checkBinding(name) or not value or name.text:match("^[a-z][A-Za-z0-9]*$") then
				continue
			end
			if value.tag == "function" then
				report(name.location, "Use camelCase for local Luau function names.")
			elseif isScalarLiteral(value) and not name.text:match("^[A-Z][A-Z0-9_]*$") then
				report(name.location, "Use camelCase for ordinary Luau scalar locals.")
			end
		end
	end
	for _, declaration in Query.findAllFromRoot(block, Utils.isStatConst).nodes do
		for index, variable in declaration.variables do
			local name = variable.name
			local value = declaration.values[index]
			if not checkBinding(name) or not value then
				continue
			end
			if value.tag == "function" and not name.text:match("^[a-z][A-Za-z0-9]*$") then
				report(name.location, "Use camelCase for local Luau function names.")
			end
			if isScalarLiteral(value) and not name.text:match("^[a-z][A-Za-z0-9]*$")
				and not name.text:match("^[A-Z][A-Z0-9_]*$") then
				report(name.location, "Use SCREAMING_SNAKE_CASE or camelCase for scalar Luau constants.")
			end
		end
	end
	local function checkPublicName(name: Syntax.CstToken<string>)
		if name.text ~= "new" and not name.text:match("^__") and not name.text:match("^[A-Z][A-Za-z0-9]*$") then
			report(name.location, "Use PascalCase for public Luau module functions.")
		end
	end
	local function checkPublicField(name: Syntax.CstToken<string>)
		if name.text:match("^_") and not name.text:match("^__") then
			report(name.location, "An exported Luau field is public. Use a local binding for private state or give the field a public name.")
		end
	end
	local function publicStringKey(key: Syntax.CstExpr): Syntax.CstToken<string>?
		if key.tag == "string" and (key.quoteStyle == "single" or key.quoteStyle == "double")
			and key.value.text:match("^[%a_][%w_]*$") then
			return key.value
		end
		return nil
	end
	local last = block.statements[#block.statements]
	local exported = if last and last.tag == "return" and #last.expressions == 1 then last.expressions[1] else nil
	local function checkReturnedFields(value: Syntax.CstExprTable)
		for _, member in value.entries do
			local key = if member.kind == "record" then member.key
				elseif member.kind == "general" then publicStringKey(member.key) else nil
			if key then
				if member.value.tag == "function" then
					checkPublicName(key)
				else
					checkPublicField(key)
				end
			end
		end
	end
	if exported and exported.tag == "table" then
		checkReturnedFields(exported)
	end
	local exportedBinding = if exported and exported.tag == "local" then exported["local"] else nil
	local ownedExport: Syntax.CstLocal?
	for _, statement in block.statements do
		if statement.tag ~= "local" and statement.tag ~= "const" then
			continue
		end
		if #statement.variables ~= 1 or #statement.values ~= 1 then
			continue
		end
		local value = statement.values[1]
		local binding = statement.variables[1]
		if statement.tag == "local" and binding.name.text:match("^[A-Z][A-Z0-9_]*$")
			and not reassigned[binding] and isScalarLiteral(value) then
			report(statement.localKeyword.location, "Declare this stable Luau constant with const.")
		end
		if value.tag == "table" and statement.variables[1] == exportedBinding then
			ownedExport = statement.variables[1]
			if not reassigned[ownedExport] then
				checkReturnedFields(value)
			end
		end
		if value.tag ~= "call" then
			continue
		end
		local callee = value.func
		if callee.tag ~= "global" or callee.name.text ~= "require" then
			continue
		end
		local argument = value.arguments[1]
		if #value.arguments ~= 1 or argument.tag ~= "string" or argument.quoteStyle == "interp" then
			continue
		end
		local name = statement.variables[1].name
		if not name.text:match("^_") and not name.text:match("^[A-Z][A-Za-z0-9]*$") then
			report(name.location, "Use PascalCase for directly required Luau module bindings.")
		end
	end
	if ownedExport and not reassigned[ownedExport] then
		local hasPublicFunction = false
		for _, statement in block.statements do
			local name: Syntax.CstExpr
			local isFunction = true
			if statement.tag == "function" then
				name = statement.name
			elseif statement.tag == "assign" and #statement.variables == 1 and #statement.values == 1 then
				name = statement.variables[1]
				isFunction = statement.values[1].tag == "function"
			else
				continue
			end
			if (name.tag == "indexname" or name.tag == "index")
				and name.expression.tag == "local" and name.expression["local"] == exportedBinding then
				local key = if name.tag == "indexname" then name.index else publicStringKey(name.index)
				if key then
					if isFunction then
						hasPublicFunction = true
						checkPublicName(key)
					else
						checkPublicField(key)
					end
				end
			end
		end
		local name = ownedExport.name
		if hasPublicFunction and not name.text:match("^_") then
			if name.text:lower() == "state" or name.text:lower() == "states" then
				report(name.location, "Name the state domain rather than using State or States for a Luau module.")
			elseif not name.text:match("^[A-Z][A-Za-z0-9]*$") then
				report(name.location, "Use PascalCase for Luau module identity tables.")
			end
		end
	end
	return findings
end)
