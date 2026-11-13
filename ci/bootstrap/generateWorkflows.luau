--!strict
-- Render the generated execution graph without launching or publishing it.
local Fs = require("@std/fs")
local Process = require("@lute/process")
local Bootstrap = require("@ci/bootstrap")
local Workflow = require("@ci/github/workflows/workflow")

local output = Process.args[2]
if not output or output == "" then error("Expected generated workflow directory", 0) end
local branch = Process.env.CI_GENERATED_BRANCH
local sha = Process.env.GITHUB_SHA
if not branch or not sha or not sha:match("^[%x]+$") or #sha ~= 40 then
	error("Generated pipeline requires branch and source revision", 0)
end
local event = Process.env.CI_EVENT or "push"
local tasks = Bootstrap.Plan(event)
local files = Workflow.Bundle(tasks, sha, branch, event)
Fs.createDirectory(output, { makeParents = true })
for name, contents in files do
	Fs.writeStringToFile(output .. "/" .. name, contents)
end
print("Generated " .. tostring(#tasks) .. " discoverable component tasks")
