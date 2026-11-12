-- ci/bootstrap/emitWorkflows.luau
--!strict
-- Read-only fixture compiler for the hosted workflow schema check.
local Fs = require("@std/fs")
local Process = require("@lute/process")
local Bootstrap = require("@ci/bootstrap")
local Workflow = require("@ci/github/workflows/workflow")

local path = Process.args[2]
if not path or path == "" then
	error("Expected output directory for generated workflow fixtures", 0)
end

Process.env.CI_OPERATION = "build"
Process.env.CI_PUBLICATION_ENABLED = "true"
Process.env.CI_EXECUTION_PREFIX = "ci/run-"
local tasks = Bootstrap.Plan("push")
local files = Workflow.Bundle(tasks, string.rep("a", 40), "ci/run-1-1", "push")
Fs.createDirectory(path, { makeParents = true })
for name, source in files do
	Fs.writeStringToFile(path .. "/" .. name, source)
end
print("Compiled " .. tostring(#tasks) .. " planned components into generated workflow fixtures")
