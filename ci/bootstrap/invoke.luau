-- ci/bootstrap/invoke.luau
--!strict

local Process = require("@lune/process")

-- The trusted coordinator inspects component contracts without executing them.
local entry = Process.args[1]
local event = Process.args[2]
if not entry or not entry:match("^ci/components/[%w_-]+/init%.luau$") then
    error("invalid CI component entry", 0)
end
if event ~= "push" and event ~= "pull_request" and event ~= "workflow_dispatch" then
    error("invalid CI event", 0)
end

local modulePath = "../../" .. entry:gsub("/init%.luau$", ""):gsub("%.luau$", "")
local implementation = require(modulePath)
if type(implementation) ~= "table" or type(implementation.new) ~= "function" then
	error(`CI component must expose a class constructor: {entry}`, 0)
end

local instance = implementation.new()
if type(instance) ~= "table" or type(instance.Run) ~= "function" then
	error(`CI component constructor must return an instance with Run: {entry}`, 0)
end

instance:Run({ event = event })
