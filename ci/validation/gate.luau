-- ci/validation/gate.luau
--!strict

local Gate = {}

--# Modules

local Process = require("@lune/process")
local Serde = require("@lune/serde")
local Rules = require("../libraries/registry/rules")

--# Functions

function Gate.Run()
	local results = Process.env.RESULTS
	local enabled = Process.env.ENABLED

	assert(results ~= nil, "missing job results")
	assert(enabled ~= nil, "missing enabled outputs")

	local context = {
		results = Serde.decode("json", results),
		enabled = Serde.decode("json", enabled),
	}
	local policy = Rules.Read("ci/validation/ruleset.json", "gate.rules")

	Rules.Validate(context, policy)
end

return Gate
