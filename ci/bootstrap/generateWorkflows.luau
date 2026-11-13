--!strict
-- Render the generated execution graph without launching or publishing it.
local Fs = require("@std/fs")
local Process = require("@lute/process")
local Bootstrap = require("@ci/bootstrap")
local Json = require("@formats/json")
local Contract = require("@ci/bootstrap/contracts/contract")
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
local selection = Process.env.CI_SELECTED_COMPONENTS
if selection and selection ~= "null" then
	local decoded: unknown = Json.decode(selection)
	if type(decoded) ~= "table" then error("Component selection must be an array", 0) end
	local requested = decoded :: { string }
	if #requested == 0 then error("Component selection cannot be empty", 0) end
	local byIdentity: { [string]: Contract.Task } = {}
	for _, task in tasks do byIdentity[task.identity] = task end
	local included: { [string]: boolean } = {}
	local function include(identity: string): ()
		if included[identity] then return end
		local task = byIdentity[identity]
		if not task then error(`Unknown or unavailable component {identity}`, 0) end
		included[identity] = true
		for _, dependency in task.needs do include(dependency) end
	end
	for index, identity in requested do
		if type(index) ~= "number" or type(identity) ~= "string" then error("Invalid component selection", 0) end
		include(identity)
	end
	local filtered: { Contract.Task } = {}
	for _, task in tasks do if included[task.identity] then table.insert(filtered, task) end end
	tasks = filtered
end
Process.env.CI_LINEAR_CONTROLLER = "true"
local files = Workflow.Bundle(tasks, sha, branch, event)
Fs.createDirectory(output, { makeParents = true })
for name, contents in files do
	Fs.writeStringToFile(output .. "/" .. name, contents)
end
print("Generated " .. tostring(#tasks) .. " discoverable component tasks")
