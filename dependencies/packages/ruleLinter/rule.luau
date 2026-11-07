-- dependencies/packages/ruleLinter/rule.luau
--!strict

local Diagnostic = require("@ruleLinter/diagnostic")

export type Context = {
	path: string,
	source: string,
}

export type Validation = (context: Context) -> { Diagnostic.Finding }

local Rule = {}
Rule.__index = Rule

type RuleFields = { validate: Validation }
export type Rule = setmetatable<RuleFields, typeof(Rule)>

function Rule.new(validate: Validation): Rule
	local fields: RuleFields = { validate = validate }
	return setmetatable(fields, Rule)
end

function Rule.Check(self: Rule, context: Context): { Diagnostic.Finding }
	return self.validate(context)
end

return Rule
