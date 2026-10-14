--!strict
local policy = require("../policy")
local context = require("../context")
local outputs = require("../../lib/outputs")
local cases = require("../../lib/cases")
local definitions = cases.read("ci/access/tests/policy.cases.json")

for _, case in definitions.policy do
    local result = policy.canPublish(cases.apply(definitions.baseline, case))
    assert(result == case.valid, case.name .. ": unexpected publication eligibility")
end
for index, case in definitions.repositories do
    assert(context.repository(case.input) == case.expected, "repository case " .. tostring(index))
end
for index, case in definitions.outputs do
    cases.check("output case " .. tostring(index), case.valid, function()
        return outputs.encode(case.input)
    end, case.expected)
end
print("Publication data cases passed")
