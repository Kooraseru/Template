-- dependencies/packages/checks/ruleLinter/rule.luau
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

--- Construct a rule around the supplied validation callback.
function Rule.new(validate: Validation): Rule
	local fields: RuleFields = { validate = validate }
	return setmetatable(fields, Rule)
end

--- Evaluate the rule against one source context and return its findings.
function Rule.Check(self: Rule, context: Context): { Diagnostic.Finding }
	return self.validate(context)
end

return Rule
