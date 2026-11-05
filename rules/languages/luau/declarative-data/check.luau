-- rules/languages/luau/declarative-data/check.luau
--!strict
-- rule-runner=lute

local query = require("@std/syntax/query")
local syntax = require("@std/syntax")
local utils = require("@std/syntax/utils")

type LintViolation = {
	lintname: string,
	location: {
		beginLine: number,
		beginColumn: number,
		endLine: number,
		endColumn: number,
	},
	message: string,
	severity: "warning",
	sourcepath: string?,
}
type Severity = "warning"

local name = "declarative_data"
local message =
	"Large uppercase boolean map may belong in JSON/TOML data or a schema; review before keeping it in Luau."

-- The editor integration sends unsaved text; inspect syntax nodes rather than reopening files by path.
local function lint(ast: syntax.AstStatBlock, sourcepath: string?, _context: unknown): { LintViolation }
	local declarations = query.findAllFromRoot(ast, utils.isStatLocal).nodes
	local violations: { LintViolation } = {}

	for _, declaration in declarations do
		if #declaration.variables ~= 1 or #declaration.values ~= 1 then
			continue
		end

		local variable = declaration.variables[1]
		local tableExpression = declaration.values[1]
		local mapName = variable.name.text

		-- Restrict the review warning to uppercase maps made entirely from true-valued fields.
		if
			not mapName:match("^[A-Z][A-Z0-9_]*$")
			or tableExpression.tag ~= "table"
			or tableExpression.entries == nil
		then
			continue
		end

		local entries = tableExpression.entries
		local isBooleanMap = #entries >= 4
		for _, entry in entries do
			local value = entry.value.node or entry.value
			if entry.kind ~= "record" or value.tag ~= "boolean" or value.value ~= true then
				isBooleanMap = false
				break
			end
		end

		if isBooleanMap then
			local severity: Severity = "warning"
			table.insert(violations, {
				lintname = name,
				location = declaration.location,
				message = `{message} ({mapName})`,
				severity = severity,
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
