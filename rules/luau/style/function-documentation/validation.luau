-- rules/luau/style/function-documentation/validation.luau
--!strict

local Diagnostic = require("@ruleLinter/diagnostic")
local Rule = require("@ruleLinter/rule")
local Comments = require("@ruleLinter/comments")
local Parser = require("@std/syntax/parser")
local Query = require("@std/syntax/query")
local Syntax = require("@std/syntax")
local Utils = require("@std/syntax/utils")

local function annotationIssue(text: string): string?
	local tag, body = text:match("^%-%-%-?%s*@([%a]+)%s*(.*)$")
	if not tag then
		return nil
	end
	if tag ~= "param" and tag ~= "return" and tag ~= "generic" and tag ~= "class" and tag ~= "field" and tag ~= "type" and tag ~= "enum" then
		return nil
	end
	if not text:match("^%-%-%-") then
		return "Start a LuaCATS @" .. tag .. " annotation with three dashes."
	end
	if not body or body == "" or (tag == "param" and not body:match("^%S+%s+%S")) then
		return "Complete the LuaCATS @" .. tag .. " annotation or remove it."
	end
	return nil
end

return Rule.new(function(context: Rule.Context): { Diagnostic.Finding }
	local findings: { Diagnostic.Finding } = {}
	local lines = context.source:split("\n")
	local docLines: { [number]: { text: string, span: Syntax.Span } } = {}
	local blockDocs: { [number]: Syntax.Span } = {}

	local function reportRange(line: number, column: number, endLine: number, endColumn: number, message: string)
		findings[#findings + 1] = {
			line = line, column = column, endLine = endLine, endColumn = endColumn,
			severity = "warning", message = message,
		}
	end

	local function report(span: Syntax.Span, message: string)
		reportRange(span.beginLine, span.beginColumn, span.endLine, span.endColumn, message)
	end
	local parsed, file = pcall(Parser.parse, context.source)
	if not parsed then
		return findings
	end
	Comments.VisitComments(file, function(comment, span, block)
		if block then
			if lines[span.beginLine]:sub(1, span.beginColumn - 1):match("^%s*$")
				and lines[span.endLine]:sub(span.endColumn):match("^%s*$") then
				blockDocs[span.endLine] = span
			end
			return
		end
		local issue = annotationIssue(comment)
		if issue then
			report(span, issue)
		end
		if comment:match("^%-%-%-") and lines[span.beginLine]:sub(1, span.beginColumn - 1):match("^%s*$") then
			docLines[span.beginLine] = { text = comment, span = span }
		end
	end)

	local function checkBlockDocs(declarationLine: number, names: { [string]: boolean }): boolean
		local span = blockDocs[declarationLine - 1]
		if not span then
			return false
		end
		if span.beginLine == span.endLine then
			local content = lines[span.beginLine]:sub(span.beginColumn, span.endColumn - 1)
			return content:match("^%-%-%[=*%[%s*[^%s@%]]") ~= nil
		end
		local opening = lines[span.beginLine]:sub(span.beginColumn):gsub("^%-%-%[=*%[", "")
		local hasProse = opening:match("^%s*[^%s@%]]") ~= nil
		local fenced, checkedSpacing = false, false
		for line = span.beginLine + 1, span.endLine - 1 do
			local content = lines[line]:match("^%s*(.-)%s*$") or ""
			if content:match("^```") then
				fenced = not fenced
			elseif not fenced and (content:match("^@param%s") or content:match("^@return%s")) then
				local column = #(lines[line]:match("^%s*") or "") + 1
				if not checkedSpacing and hasProse and not lines[line - 1]:match("^%s*$") then
					reportRange(line, column, line, column + #content,
						"Leave a blank line between Moonwave prose and its annotation tags.")
				end
				checkedSpacing = true
				local name = content:match("^@param%s+([%a_][%w_]*)%??%s+%S")
				if name and not names[name] then
					reportRange(line, column, line, column + #content,
						"Block documentation names a parameter absent from this declaration: " .. name .. ".")
				end
			elseif not fenced and content ~= "" and not content:match("^@") then
				hasProse = true
			end
		end
		return hasProse
	end

	local function checkFunctionDocs(func: Syntax.CstExprFunction, declaration: Syntax.Span, public: boolean?, moduleHelper: boolean?)
		local declarationLine = declaration.beginLine
		local names: { [string]: boolean } = {}
		for _, parameter in func.parameters do
			names[parameter.name.text] = true
		end
		if func.self then
			names.self = true
		end
		local hasProse = checkBlockDocs(declarationLine, names)
		local line = declarationLine - 1
		while docLines[line] do
			local doc = docLines[line]
			if doc.text:match("^%-%-%-%s*[^%s@%-]") then
				hasProse = true
			end
			local name = doc.text:match("^%-%-%-%s*@param%s+([%a_][%w_]*)%??%s+%S")
			if name and not names[name] then
				report(doc.span, "LuaCATS documents a parameter absent from this declaration: " .. name .. ".")
			end
			local tag = doc.text:match("^%-%-%-%s*@([%a_]+)%f[^%w_]")

			if tag == "readonly" then
				report(doc.span, "Reserve @readonly for property documentation.")
			elseif tag == "function" or tag == "method" then
				report(doc.span, "Remove this declaration tag from a function already declared in Luau.")
			end

			line -= 1
		end

		local branches = 0
		for _, statement in func.body.statements do
			if statement.tag == "conditional" then
				branches += 1 + #statement.elseifs
			end
		end
		if not hasProse and (public or moduleHelper or branches >= 3 or #func.body.statements >= 20) then
			local firstLine = lines[declarationLine]
			reportRange(declarationLine, declaration.beginColumn, declarationLine, #firstLine:gsub("\r$", "") + 1,
				if public then "Document this exported function's purpose or observable contract above its declaration."
				else "Document this function's purpose and any important ordering, side effects, or failure behavior above its declaration.")
		end
	end

	local exported: { [Syntax.CstLocal]: boolean } = {}
	local moduleHelpers: { [Syntax.CstLocal]: boolean } = {}
	local publicNames: { [Syntax.CstExpr]: boolean } = {}
	for _, statement in file.root.statements do
		if statement.tag == "return" then
			for _, expression in statement.expressions do
				if expression.tag == "local" then
					exported[expression["local"]] = true
				end
			end
		elseif statement.tag == "localfunction" then
			moduleHelpers[statement.name] = true
		elseif statement.tag == "function" then
			publicNames[statement.name] = true
		end
	end

	for _, declaration in Query.findAllFromRoot(file.root, Utils.isStatLocalFunction).nodes do
		checkFunctionDocs(declaration.func, declaration.location, false, moduleHelpers[declaration.name])
	end
	for _, declaration in Query.findAllFromRoot(file.root, Utils.isStatFunction).nodes do
		local name = declaration.name
		local public = publicNames[name] == true and (name.tag == "indexname" or name.tag == "index")
			and name.expression.tag == "local" and exported[name.expression["local"]] == true
		checkFunctionDocs(declaration.func, declaration.location, public)
	end
	for _, statement in file.root.statements do
		if (statement.tag == "local" or statement.tag == "const") and #statement.variables == 1 then
			local value = statement.values[1]
			if value and value.tag == "function" then
				checkFunctionDocs(value, statement.location, false, true)
			end
		end
		if statement.tag ~= "assign" or #statement.variables ~= 1 or #statement.values ~= 1 then
			continue
		end
		local name, value = statement.variables[1], statement.values[1]
		if (name.tag == "indexname" or name.tag == "index")
			and name.expression.tag == "local" and exported[name.expression["local"] :: Syntax.CstLocal]
			and value.tag == "function" then
			checkFunctionDocs(value, statement.location, true)
		end
	end
	return findings
end)
