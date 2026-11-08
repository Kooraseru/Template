-- rules/luau/design/objects/validation.luau
--!strict

local Diagnostic = require("@ruleLinter/diagnostic")
local Parser = require("@std/syntax/parser")
local Query = require("@std/syntax/query")
local Syntax = require("@std/syntax")
local Rule = require("@ruleLinter/rule")
local Utils = require("@std/syntax/utils")

return Rule.new(function(context: Rule.Context): { Diagnostic.Finding }
	local parsed, block = pcall(Parser.parseBlock, context.source)
	if not parsed then
		return {}
	end
	local findings: { Diagnostic.Finding } = {}
	local ownedTables: { [Syntax.CstLocal]: boolean } = {}
	local instanceMetatables: { [Syntax.CstLocal]: boolean } = {}
	for _, declaration in Query.findAllFromRoot(block, Utils.isStatConst).nodes do
		for index, binding in declaration.variables do
			local initializer = declaration.values[index]
			if initializer and initializer.tag == "table" then
				ownedTables[binding] = true
			end
		end
	end
	for _, declaration in Query.findAllFromRoot(block, Utils.isStatLocal).nodes do
		for index, binding in declaration.variables do
			local initializer = declaration.values[index]
			if initializer and initializer.tag == "table" then
				ownedTables[binding] = true
			end
		end
	end
	for _, assignment in Query.findAllFromRoot(block, Utils.isStatAssign).nodes do
		for _, target in assignment.variables do
			if target.tag == "local" then
				ownedTables[target["local"]] = nil
			end
		end
	end
	local calls = Query.findAllFromRoot(block, Utils.isExprCall).nodes
	for _, call in calls do
		local callee = call.func
		if callee.tag ~= "global" or callee.name.text ~= "setmetatable" or #call.arguments ~= 2 then
			continue
		end
		local fields = call.arguments[1]
		local metatable = call.arguments[2]
		if metatable.tag ~= "local" or not ownedTables[metatable["local"]] then
			continue
		end
		instanceMetatables[metatable["local"]] = true
		if fields.tag ~= "table" or #fields.entries == 0 then
			continue
		end
		local namedFields = true
		for _, field in fields.entries do
			if field.kind ~= "record" then
				namedFields = false
				break
			end
		end
		if not namedFields then
			continue
		end
		local span = fields.location
		findings[#findings + 1] = {
			line = span.beginLine, column = span.beginColumn,
			endLine = span.endLine, endColumn = span.endColumn,
			severity = "warning", message = "Declare instance fields before passing them to setmetatable.",
		}
	end
	for _, call in calls do
		local callee = call.func
		if callee.tag ~= "global" or callee.name.text ~= "setmetatable" or #call.arguments ~= 2 then
			continue
		end
		local derived = call.arguments[1]
		local metadata = call.arguments[2]
		if derived.tag ~= "local" or not instanceMetatables[derived["local"]] or metadata.tag ~= "table" or #metadata.entries ~= 1 then
			continue
		end
		for _, entry in metadata.entries do
			if entry.kind ~= "record" or entry.key.text ~= "__index" then
				continue
			end
			local base = entry.value
			if base.tag ~= "local" or base["local"] == derived["local"] or not instanceMetatables[base["local"]] then
				continue
			end
			local span = entry.location
			findings[#findings + 1] = {
				line = span.beginLine, column = span.beginColumn,
				endLine = span.endLine, endColumn = span.endColumn,
				severity = "warning", message = "This class inherits from another local class. Prefer composition unless inheritance is needed.",
			}
		end
	end
	for _, declaration in Query.findAllFromRoot(block, Utils.isStatFunction).nodes do
		local name = declaration.name
		if name.tag ~= "indexname" then
			continue
		end
		local receiver = name.expression
		if receiver.tag ~= "local" or not instanceMetatables[receiver["local"]] then
			continue
		end
		local first = declaration.func.parameters[1]
		local implicit = name.accessor.text == ":"
		if not implicit and (not first or first.name.text ~= "self" or first.annotation) then
			continue
		end
		local span = if implicit then name.location else first.name.location
		findings[#findings + 1] = {
			line = span.beginLine, column = span.beginColumn,
			endLine = span.endLine, endColumn = span.endColumn,
			severity = "warning", message = "Declare project-owned instance methods with dot syntax and an explicitly typed self parameter.",
		}
	end
	return findings
end)
