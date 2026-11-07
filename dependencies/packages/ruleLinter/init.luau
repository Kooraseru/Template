-- dependencies/packages/ruleLinter/init.luau
--!strict

local Discovery = require("@ruleLinter/discovery")
local Runner = require("@ruleLinter/runner")
local Rule = require("@ruleLinter/rule")
local Diagnostic = require("@ruleLinter/diagnostic")

local function check(sources: { Rule.Context }): ({ Diagnostic.Diagnostic }, number)
	local entries = Discovery.Discover()
	return Runner.Run(entries, sources), #entries
end

return { Check = check }
