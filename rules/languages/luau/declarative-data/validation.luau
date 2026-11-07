-- rules/languages/luau/declarative-data/validation.luau
--!strict

local Rule = require("@ruleLinter/rule")
local Diagnostic = require("@ruleLinter/diagnostic")
local parser = require("@std/syntax/parser")
local query = require("@std/syntax/query")
local syntax = require("@std/syntax")
local utils = require("@std/syntax/utils")

type LintViolation = {
	lintname: string,
	location: syntax.Span,
	message: string,
	severity: "warning",
	sourcepath: string?,
	related: { syntax.Span }?,
}

type Candidate = {
	binding: syntax.CstLocal,
	declaration: syntax.CstStatLocal | syntax.CstStatConst,
	initial: syntax.CstExprTable,
}

local RULE_NAME = "declarative_data"
local MESSAGE = "This table contains static declarative data; move it to a data file or document the runtime constraint."

-- Recognize serializable literal values, recursively, without relying on identifier spelling.
local function isStatic(value: syntax.CstExpr): boolean
	if value.tag == "boolean" or value.tag == "string" or value.tag == "number" or value.tag == "integer" or value.tag == "nil" then
		return true
	end
	if value.tag == "unary" then
		return value.operator.text == "-" and isStatic(value.operand)
	end
	if value.tag == "group" then
		return isStatic(value.expression)
	end
	if value.tag ~= "table" then
		return false
	end
	for _, entry in value.entries do
		if entry.kind == "general" and not isStatic(entry.key) then
			return false
		end
		if not isStatic(entry.value) then
			return false
		end
	end
	return true
end

-- A CST local reference identifies its original binding, including shadowed names.
local function bindingOf(expression: syntax.CstExpr): syntax.CstLocal?
	if expression.tag == "local" then
		return expression["local"]
	end
	if expression.tag == "index" or expression.tag == "indexname" then
		return bindingOf(expression.expression)
	end
	return nil
end

-- Follow local aliases only when the alias binding is never reassigned.
local function resolveAlias(binding: syntax.CstLocal, aliases: { [syntax.CstLocal]: syntax.CstLocal }): syntax.CstLocal
	local current = binding
	local visited: { [syntax.CstLocal]: boolean } = {}
	while aliases[current] and not visited[current] do
		visited[current] = true
		current = aliases[current]
	end
	return current
end

local function isInside(outer: syntax.Span, inner: syntax.Span): boolean
	local startsAfter = inner.beginLine > outer.beginLine or (inner.beginLine == outer.beginLine and inner.beginColumn >= outer.beginColumn)
	local endsBefore = inner.endLine < outer.endLine or (inner.endLine == outer.endLine and inner.endColumn <= outer.endColumn)
	return startsAfter and endsBefore
end

local function inRuntimeScope(location: syntax.Span, scopes: { syntax.Span }): boolean
	for _, scope in scopes do
		if isInside(scope, location) then
			return true
		end
	end
	return false
end

local function findDeclaration(node: syntax.CstNode): (syntax.CstStatLocal | syntax.CstStatConst)?
	local declaration = utils.isStatLocal(node)
	if declaration then
		return declaration
	end
	return utils.isStatConst(node)
end

local function findLoop(node: syntax.CstNode): (syntax.CstStatFor | syntax.CstStatForIn | syntax.CstStatWhile | syntax.CstStatRepeat)?
	local numeric = utils.isStatFor(node)
	if numeric then
		return numeric
	end
	local generic = utils.isStatForIn(node)
	if generic then
		return generic
	end
	local loop = utils.isStatWhile(node)
	if loop then
		return loop
	end
	return utils.isStatRepeat(node)
end

local function lint(ast: syntax.CstStatBlock, sourcepath: string?, _context: unknown): { LintViolation }
	local candidates: { Candidate } = {}
	local scopes: { syntax.Span } = {}
	local hasBehavior: { [syntax.CstLocal]: boolean } = {}
	local mutatedAtRuntime: { [syntax.CstLocal]: boolean } = {}
	local stagedStatic: { [syntax.CstLocal]: { syntax.Span } } = {}
	local uncertain: { [syntax.CstLocal]: boolean } = {}
	local aliases: { [syntax.CstLocal]: syntax.CstLocal } = {}
	local reassigned: { [syntax.CstLocal]: boolean } = {}
	local knownFunctions: { [syntax.CstLocal]: boolean } = {}
	local violations: { LintViolation } = {}

	-- Reject alias propagation across a reassignment; the table identity could have changed.
	for _, statement in query.findAllFromRoot(ast, utils.isStatAssign).nodes do
		for _, target in statement.variables do
			if target.tag == "local" then
				reassigned[target["local"]] = true
			end
		end
	end

	-- `const` and `local` are equivalent for this rule; neither makes a table data or behavior.
	for _, declaration in query.findAllFromRoot(ast, findDeclaration).nodes do
		if #declaration.variables == 1 and #declaration.values == 1 then
			local binding = declaration.variables[1]
			local initial = declaration.values[1]
			if initial.tag == "table" then
				table.insert(candidates, { binding = binding, declaration = declaration, initial = initial })
			elseif initial.tag == "local" and not reassigned[binding] then
				aliases[binding] = initial["local"]
			elseif initial.tag == "function" then
				knownFunctions[binding] = true
			end
		end
	end

	-- Distinguish mutations during execution from one-time module initialization.
	for _, statement in query.findAllFromRoot(ast, utils.isStatFunction).nodes do
		table.insert(scopes, statement.func.body.location)
		if statement.name.tag == "index" or statement.name.tag == "indexname" then
			local binding = bindingOf(statement.name)
			if binding then
				hasBehavior[resolveAlias(binding, aliases)] = true
			end
		end
	end
	for _, statement in query.findAllFromRoot(ast, utils.isStatLocalFunction).nodes do
		table.insert(scopes, statement.func.body.location)
		knownFunctions[statement.name] = true
	end
	for _, statement in query.findAllFromRoot(ast, findLoop).nodes do
		table.insert(scopes, statement.body.location)
	end

	-- Assignments to members can install methods, modify runtime state, or merely stage static data.
	for _, statement in query.findAllFromRoot(ast, utils.isStatAssign).nodes do
		for index, target in statement.variables do
			if target.tag ~= "index" and target.tag ~= "indexname" then
				continue
			end
			local original = bindingOf(target)
			if not original then
				continue
			end
			local binding = resolveAlias(original, aliases)
			local value = statement.values[index]
			if value and value.tag == "function" then
				hasBehavior[binding] = true
			elseif inRuntimeScope(statement.location, scopes) then
				mutatedAtRuntime[binding] = true
			elseif value and isStatic(value) and (target.tag == "indexname" or isStatic(target.index)) then
				local assignments = stagedStatic[binding] or {}
				table.insert(assignments, statement.location)
				stagedStatic[binding] = assignments
			else
				uncertain[binding] = true
			end
		end
	end
	for _, statement in query.findAllFromRoot(ast, utils.isStatCompoundAssign).nodes do
		local original = bindingOf(statement.variable)
		if original then
			mutatedAtRuntime[resolveAlias(original, aliases)] = true
		end
	end

	-- Track standard collection operations and opaque calls that may mutate an escaped table.
	for _, call in query.findAllFromRoot(ast, utils.isExprCall).nodes do
		local collectionMethod = call.func.tag == "indexname"
			and call.func.expression.tag == "global"
			and call.func.expression.name.text == "table"
			and (call.func.index.text == "insert" or call.func.index.text == "remove" or call.func.index.text == "clear" or call.func.index.text == "sort")
		if collectionMethod then
			local first = call.arguments[1]
			local original = first and bindingOf(first)
			if original then
				local binding = resolveAlias(original, aliases)
				if inRuntimeScope(call.location, scopes) then
					mutatedAtRuntime[binding] = true
				else
					uncertain[binding] = true
				end
			end
			continue
		end

		local opaqueCall = (call.func.tag == "local" and not knownFunctions[call.func["local"]])
			or (call.func.tag == "indexname" and call.func.expression.tag == "local")
		if opaqueCall then
			for _, argument in call.arguments do
				local original = bindingOf(argument)
				if original then
					uncertain[resolveAlias(original, aliases)] = true
				end
			end
		end
	end

	for _, candidate in candidates do
		local binding = candidate.binding
		local initial = candidate.initial
		if hasBehavior[binding] or mutatedAtRuntime[binding] or uncertain[binding] or not isStatic(initial) then
			continue
		end
		if #initial.entries == 0 and not stagedStatic[binding] then
			continue
		end
		violations[#violations + 1] = {
			lintname = RULE_NAME,
			location = candidate.declaration.location,
			related = stagedStatic[binding],
			message = MESSAGE,
			severity = "warning",
			sourcepath = sourcepath,
		}
	end

	-- A bare static module return has no binding declaration to visit above.
	for _, statement in ast.statements do
		if statement.tag == "return" then
			for _, expression in statement.expressions do
				if expression.tag == "table" and #expression.entries > 0 and isStatic(expression) then
					violations[#violations + 1] = {
						lintname = RULE_NAME,
						location = expression.location,
						message = MESSAGE,
						severity = "warning",
						sourcepath = sourcepath,
					}
				end
			end
		end
	end

	return violations
end

return Rule.new(function(context: Rule.Context): { Diagnostic.Finding }
	local path = context.path:gsub("\\", "/")
	for segment in path:gmatch("[^/]+") do
		if segment == "tests" or segment == "examples" or segment == "vendor" or segment == "generated" or segment == "build" or segment == "node_modules" then
			return {}
		end
	end
	local parsed, ast = pcall(parser.parseBlock, context.source)
	if not parsed then
		-- Lute reports syntax errors separately.
		return {}
	end
	local findings: { Diagnostic.Finding } = {}
	for _, violation in lint(ast, path, nil) do
		local span = violation.location
		local related: { Diagnostic.Span } = {}
		for _, assignment in violation.related or {} do
			table.insert(related, {
				line = assignment.beginLine, column = assignment.beginColumn,
				endLine = assignment.endLine, endColumn = assignment.endColumn,
			})
		end
		findings[#findings + 1] = {
			line = span.beginLine,
			column = span.beginColumn,
			endLine = span.endLine,
			endColumn = span.endColumn,
			severity = "error", related = related,
			message = violation.message,
		}
	end
	return findings
end)
