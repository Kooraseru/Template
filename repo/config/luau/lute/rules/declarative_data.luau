--!strict

local query = require("@std/syntax/query")
local syntax = require("@std/syntax")
local utils = require("@std/syntax/utils")

type LintViolation = {
	lintname: string,
	location: any,
	message: string,
	severity: "warning",
	sourcepath: any?,
}

local name = "declarative_data"
local message =
	"Large uppercase boolean map may belong in JSON/TOML data or a schema; review before keeping it in Luau."

-- The editor integration sends unsaved text; inspect syntax nodes rather than reopening files by path.
local function lint(ast: syntax.AstStatBlock, sourcepath: any?, _context: any): { LintViolation }
	local declarations = query.findAllFromRoot(ast, utils.isStatLocal).nodes
	local violations: { LintViolation } = {}

	for _, declaration in declarations do
		if #declaration.variables ~= 1 or #declaration.values ~= 1 then
			continue
		end

		local variable = declaration.variables[1].node
		local tableExpression = declaration.values[1].node
		local mapName = variable.name.text

		-- Restrict the review warning to uppercase maps made entirely from true-valued fields.
		if not mapName:match("^[A-Z][A-Z0-9_]*$") or tableExpression.tag ~= "table" then
			continue
		end

		local isBooleanMap = #tableExpression.entries >= 4
		for _, entry in tableExpression.entries do
			local value = if entry.value.node ~= nil then entry.value.node else entry.value
			if entry.kind ~= "record" or value.tag ~= "boolean" or value.value ~= true then
				isBooleanMap = false
				break
			end
		end

		if isBooleanMap then
			table.insert(violations, {
				lintname = name,
				location = declaration.location,
				message = `{message} ({mapName})`,
				severity = "warning" :: "warning",
				sourcepath = sourcepath,
			})
		end
	end

	return violations
end

local rule = {
	name = name,
	lint = lint,
}

return table.freeze(rule)
