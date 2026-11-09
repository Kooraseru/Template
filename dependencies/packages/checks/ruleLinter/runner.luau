-- dependencies/packages/checks/ruleLinter/runner.luau
--!strict

local Diagnostic = require("@ruleLinter/diagnostic")
local Rule = require("@ruleLinter/rule")

local function loadRule(entry: string): unknown
	local modulePath = "@workspace/" .. entry:gsub("/init%.luau$", ""):gsub("%.luau$", "")
	local loaded, result = pcall(require, modulePath)
	if not loaded then
		error(tostring(result), 0)
	end
	return result
end

local function configure(module: unknown, settings: unknown): Rule.Rule
	local result = module

	if type(module) == "table" then
		local create = (module :: { [string]: unknown }).Create
		if type(create) == "function" then
			result = (create :: (unknown) -> unknown)(settings)
		end
	end

	if type(result) ~= "table" or type(result.Check) ~= "function" then
		error("Rule does not implement Check", 0)
	end
	return result :: Rule.Rule
end

local function check(validator: Rule.Rule, identity: string, sources: { Rule.Context }): { Diagnostic.Diagnostic }
	local diagnostics: { Diagnostic.Diagnostic } = {}
	for _, source in sources do
		local checked, findings = pcall(validator.Check, validator, source)
		if not checked then
			error("Rule " .. identity .. " failed while checking " .. source.path .. ": " .. tostring(findings), 0)
		end
		for _, finding in findings do
			table.insert(diagnostics, { path = source.path, rule = identity, finding = finding })
		end
	end
	return diagnostics
end

local function run(entries: { string }, sources: { Rule.Context }): { Diagnostic.Diagnostic }
	local diagnostics: { Diagnostic.Diagnostic } = {}
	for _, entry in entries do
		local directory = entry:gsub("/validation/init%.luau$", ""):gsub("/validation%.luau$", "")
		local identity = "luau/" .. (directory:match("[^/]+$") or directory)
		for _, diagnostic in check(configure(loadRule(entry), nil), identity, sources) do
			table.insert(diagnostics, diagnostic)
		end
	end
	return diagnostics
end

return { Load = loadRule, Configure = configure, Check = check, Run = run }
