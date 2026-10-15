--!strict
local process = require("@lune/process")
local serde = require("@lune/serde")
local rules = require("../lib/rules")

local results = assert(process.env.RESULTS, "missing job results")
local enabled = assert(process.env.ENABLED, "missing enabled outputs")
local context = {
    results = serde.decode("json", results),
    enabled = serde.decode("json", enabled),
}
rules.validate(context, rules.read("ci/validation/ruleset.json", "gate.rules"))
print("CI gate passed")
