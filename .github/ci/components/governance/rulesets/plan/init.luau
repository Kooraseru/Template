-- .github/ci/components/governance/rulesets/plan/init.luau
--!strict

local Fs = require("@std/fs")
local Json = require("@formats/json")
local RulesetCatalog = require("@ci/integrations/github/resources/rulesets/rulesetCatalog")

local Component = {}
Component.__index = Component
export type Component = setmetatable<{}, typeof(Component)>

function Component.new(): Component
	return setmetatable({}, Component)
end

function Component.Run(_self: Component, _context: { event: string }): ()
	local definitions = RulesetCatalog.Read()
	Fs.createDirectory("build/github/ruleset-plans", { makeParents = true })
	Fs.writeStringToFile(
		"build/github/ruleset-plans/index.json",
		Json.encode({
			rulesets = definitions,
			applied = false,
			note = "Validated local rulesets only. The privileged rulesets/sync component applies them on source pushes.",
		})
	)
	print(`Validated {#definitions} managed ruleset definitions; no remote rules were changed.`)
end

return Component
