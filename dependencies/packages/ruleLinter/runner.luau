-- dependencies/packages/ruleLinter/runner.luau
--!strict

--# Modules

local Diagnostic = require("@ruleLinter/diagnostic")
local Rule = require("@ruleLinter/rule")

--# Helpers

--- Resolves the rule identity from its validation module path.
local function get_rule_identity(entry: string): string
	local identity = entry
		:gsub("/validation/init%.luau$", "")
		:gsub("/validation%.luau$", "")

	return identity
end

--- Loads a rule and verifies that it exposes the required Check method.
local function load_rule(entry: string, identity: string): Rule.Rule
	local module_path = `@workspace/{entry:gsub("%.luau$", "")}`
	local loaded, result = pcall(require, module_path)

	if not loaded then
		error(`Failed to load rule {identity}: {tostring(result)}`, 0)
	end

	if type(result) ~= "table" or type(result.Check) ~= "function" then
		error(`Rule {identity} does not implement Check`, 0)
	end

	return result :: Rule.Rule
end

--# Functions

--- Executes discovered rules against the supplied sources.
--- @param entries Paths to rule validation modules.
--- @param sources Source contexts to validate.
--- @return Collected diagnostics from all rule checks.
local function run(entries: { string }, sources: { Rule.Context }): { Diagnostic.Diagnostic }
	--# Variables

	local diagnostics: { Diagnostic.Diagnostic } = {}

	-- Execute each rule against every source.
	for _, entry in entries do
		local identity = get_rule_identity(entry)
		local validator = load_rule(entry, identity)

		for _, source in sources do
			local findings = validator:Check(source)

			-- Associate each finding with its source and rule.
			for _, finding in findings do
				table.insert(diagnostics, {
					path = source.path,
					rule = identity,
					finding = finding,
				})
			end
		end
	end

	return diagnostics
end

return {
	Run = run,
}
