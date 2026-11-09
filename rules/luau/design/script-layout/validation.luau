-- rules/luau/design/script-layout/validation.luau
--!strict

local Comments = require("@ruleLinter/comments")
local Diagnostic = require("@ruleLinter/diagnostic")
local Rule = require("@ruleLinter/rule")
local Parser = require("@std/syntax/parser")
local Syntax = require("@std/syntax")

type Roles = { [string]: { string } }
type Member = { owner: Syntax.CstLocal, name: string?, func: Syntax.CstExprFunction, method: boolean }
type Declaration = { span: Syntax.Span, role: string?, member: Member?, binding: Syntax.CstLocal?, constructor: boolean? }
type Marker = { name: string, span: Syntax.Span }

local layouts: Roles = {
	["function-module"] = { "Modules", "Types", "Constants", "Helpers", "Functions" },
	["table-module"] = { "Modules", "Types", "Constants", "Variables", "Helpers", "Functions" },
	object = { "Modules", "Types", "Constants", "Helpers", "Functions", "Constructor", "Methods" },
	["entry-point"] = { "Modules", "Types", "Constants", "Helpers", "Initialization" },
	["ecs-component"] = { "Types", "Constants" },
	["ecs-system"] = { "Modules", "Types", "Constants", "Helpers", "Functions" },
}

--- Identifies a callable member through its local receiver binding, even if another scope uses the same name.
local function memberOf(target: Syntax.CstExpr, func: Syntax.CstExprFunction): Member?
	if target.tag ~= "indexname" and target.tag ~= "index" then
		return nil
	end
	local receiver = target.expression
	if receiver.tag ~= "local" then
		return nil
	end
	return {
		owner = receiver["local"],
		name = if target.tag == "indexname" then target.index.text else nil,
		func = func,
		method = func.self ~= nil or (func.parameters[1] ~= nil and func.parameters[1].name.text == "self"),
	}
end

--- Recognizes a constructor that returns an instance using the exported module as its metatable.
local function constructsInstance(member: Member): boolean
	if member.name ~= "new" then
		return false
	end
	for _, statement in member.func.body.statements do
		if statement.tag ~= "return" then
			continue
		end
		local result = statement.expressions[1]
		if result and result.tag == "call" then
			local callee = result.func
			if callee.tag ~= "global" or callee.name.text ~= "setmetatable" then
				continue
			end
			local metatable = result.arguments[2]
			if metatable and metatable.tag == "local" and metatable["local"] == member.owner then
				return true
			end
		end
	end
	return false
end

--- Records top-level roles and infers module shape from a single returned value.
local function inspect(statements: { Syntax.CstStat }): (string?, { Declaration })
	local tables: { [Syntax.CstLocal]: boolean } = {}
	local callables: { [Syntax.CstLocal]: boolean } = {}
	local members: { [Syntax.CstLocal]: boolean } = {}
	local constructors: { [Syntax.CstLocal]: boolean } = {}
	local declarations: { Declaration } = {}
	local exported: Syntax.CstExpr? = nil

	for _, statement in statements do
		local declaration: Declaration = { span = statement.location }
		if statement.tag == "local" or statement.tag == "const" then
			for index, binding in statement.variables do
				local value = statement.values[index]
				if value and value.tag == "table" then
					tables[binding] = true
					for _, item in value.entries do
						if item.value.tag == "function" then
							members[binding] = true
						end
					end
				elseif value and value.tag == "function" then
					callables[binding] = true
				end
			end
			local value = statement.values[1]
			if #statement.variables == 1 and value then
				if value.tag == "call" and value.func.tag == "global" and value.func.name.text == "require" then
					declaration.role = "Modules"
				elseif value.tag == "function" then
					declaration.binding = statement.variables[1]
					declaration.role = "Helpers"
				elseif statement.tag == "const" and (value.tag == "string" or value.tag == "number" or value.tag == "boolean") then
					declaration.role = "Constants"
				end
			end
		elseif statement.tag == "localfunction" then
			callables[statement.name] = true
			declaration.binding = statement.name
			declaration.role = "Helpers"
		elseif statement.tag == "function" then
			declaration.member = memberOf(statement.name, statement.func)
			declaration.role = "Functions"
		elseif statement.tag == "assign" then
			for index, target in statement.variables do
				local value = statement.values[index]
				if target.tag == "local" then
					tables[target["local"]] = nil
					callables[target["local"]] = nil
				elseif value and value.tag == "function" and #statement.variables == 1 then
					declaration.member = memberOf(target, value)
					declaration.role = "Functions"
				end
			end
		elseif statement.tag == "typealias" or statement.tag == "typefunction" then
			declaration.role = "Types"
		elseif statement.tag == "return" then
			if #statement.expressions == 1 then
				exported = statement.expressions[1]
				if exported.tag == "function" then
					declaration.role = "Functions"
				end
			end
		end

		local member = declaration.member
		if member then
			members[member.owner] = true
			declaration.constructor = constructsInstance(member)
			if declaration.constructor then
				constructors[member.owner] = true
			end
		end
		table.insert(declarations, declaration)
	end

	local shape: string? = nil
	if exported and exported.tag == "local" then
		local binding = exported["local"]
		if tables[binding] and constructors[binding] then
			shape = "object"
		elseif callables[binding] then
			shape = "function-module"
		elseif tables[binding] and members[binding] then
			shape = "table-module"
		end

		for _, declaration in declarations do
			local member = declaration.member
			if declaration.binding == binding and shape == "function-module" then
				declaration.role = "Functions"
			elseif member and member.owner == binding and shape == "object" then
				declaration.role = if declaration.constructor then "Constructor" elseif member.method then "Methods" else "Functions"
			end
		end
	elseif exported and exported.tag == "function" then
		shape = "function-module"
	elseif exported and exported.tag == "table" then
		for _, entry in exported.entries do
			if entry.value.tag == "function" then
				shape = "table-module"
				break
			end
		end
	end
	return shape, declarations
end

--- Builds the workspace path lookup once for each rule configuration.
local function create(settings: unknown): Rule.Rule
	local declared: { [string]: string } = {}
	if type(settings) == "table" then
		local pathKinds: { [string]: string } = { entryPoints = "entry-point", ecsComponents = "ecs-component", ecsSystems = "ecs-system" }
		for field, shape in pathKinds do
			local paths = (settings :: { [string]: unknown })[field]
			if type(paths) == "table" then
				for _, path in paths do
					if type(path) == "string" then
						if declared[path] then
							error(`Script layout path is declared more than once: {path}`, 0)
						end
						declared[path] = shape
					end
				end
			end
		end
	end

	return Rule.new(function(context: Rule.Context): { Diagnostic.Finding }
		if not context.source:find("--#", 1, true) then
			return {}
		end
		local parsed, file = pcall(Parser.parse, context.source)
		if not parsed then
			return {}
		end
		local inferred, declarations = inspect(file.root.statements)
		local shape = declared[context.path:gsub("\\", "/")] or inferred
		if not shape then
			return {}
		end

		local markers: { Marker } = {}
		Comments.VisitComments(file, function(comment, span, block)
			local name = if not block and span.beginColumn == 1 then comment:match("^%-%-#%s+([%w ]-)%s*$") else nil
			if name then
				table.insert(markers, { name = name, span = span })
			end
		end)
		table.sort(markers, function(a: Marker, b: Marker)
			return a.span.beginLine < b.span.beginLine
		end)

		local topLevelMarkers: { Marker } = {}
		local statementIndex = 1
		for _, marker in markers do
			while declarations[statementIndex] and declarations[statementIndex].span.endLine < marker.span.beginLine do
				statementIndex += 1
			end
			local statement = declarations[statementIndex]
			if not statement or marker.span.beginLine < statement.span.beginLine then
				table.insert(topLevelMarkers, marker)
			end
		end

		local findings: { Diagnostic.Finding } = {}
		local function report(span: Syntax.Span, message: string)
			findings[#findings + 1] = {
				line = span.beginLine, column = span.beginColumn,
				endLine = span.endLine, endColumn = span.endColumn,
				severity = "warning", message = message,
			}
		end

		local order: { [string]: number } = {}
		for index, name in layouts[shape] do
			order[name] = index
		end
		local seen: { [string]: boolean } = {}
		local latest = 0
		local cursor = 1
		for index, marker in topLevelMarkers do
			local position = order[marker.name]
			if not position then
				report(marker.span, `Section {marker.name} does not belong in a {shape}.`)
			elseif seen[marker.name] then
				report(marker.span, `Section {marker.name} appears more than once.`)
			elseif position < latest then
				report(marker.span, `Section {marker.name} is out of order for a {shape}.`)
			end
			seen[marker.name] = true
			latest = math.max(latest, position or 0)
			local nextMarker = topLevelMarkers[index + 1]
			while cursor <= #declarations do
				local declaration = declarations[cursor]
				if nextMarker and declaration.span.beginLine >= nextMarker.span.beginLine then
					break
				end
				if position and declaration.span.beginLine > marker.span.beginLine and declaration.role
					and declaration.role ~= marker.name then
					report(declaration.span, `Move this declaration from {marker.name} to {declaration.role}.`)
				end
				cursor += 1
			end
		end
		return findings
	end)
end

return { Create = create }
