-- ci/validation/gate.luau
--!strict
local Process = require("@lune/process")
local Serde = require("@lune/serde")
local Rules = require("../lib/rules")

local results = assert(Process.env.RESULTS, "missing job results")
local enabled = assert(Process.env.ENABLED, "missing enabled outputs")
local context = {
    results = Serde.decode("json", results),
    enabled = Serde.decode("json", enabled),
}
Rules.Validate(context, Rules.Read("ci/validation/ruleset.json", "gate.rules"))
print("CI gate passed")
