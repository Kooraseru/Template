-- dependencies/packages/checks/preflightChecker/bootstrap/plan.luau
--!strict

local Bootstrap = require("@ci/bootstrap")
local Json = require("@formats/json")
local Process = require("@lute/process")

local event = Process.args[2]
if event ~= "push" and event ~= "pull_request" and event ~= "workflow_dispatch" then
	error("Expected push, pull_request, or workflow_dispatch", 0)
end

print(Json.encode(Bootstrap.new(event):BuildPlan()))
