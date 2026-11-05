-- .github/ci/components/governance/rulesets/plan/init.luau
--!strict

local Fs = require("@lune/fs")
local Serde = require("@lune/serde")
local RulesetCatalog = require("@ci/integrations/github/resources/rulesets/rulesetCatalog")

local Component = {}
Component.__index = Component
export type Component = setmetatable<{}, typeof(Component)>

function Component.new(): Component
	return setmetatable({}, Component)
end

function Component.Run(_self: Component, _context: { event: string }): ()
	local definitions = RulesetCatalog.Read()
	Fs.writeDir("build/github/ruleset-plans")
	Fs.writeFile(
		"build/github/ruleset-plans/index.json",
		Serde.encode("json", {
			rulesets = definitions,
			applied = false,
			note = "Validated local rulesets only. The privileged rulesets/sync component applies them on source pushes.",
		})
	)
	print(`Validated {#definitions} managed ruleset definitions; no remote rules were changed.`)
end

return Component
