--!strict

-- Execute only a validated component entry. Contract discovery never requires it.
local Process = require("@lune/process")

local entry = Process.args[1]
local event = Process.args[2]
if not entry or not entry:match("^ci/components/[%w_/%-]+%.luau$") or entry:find("//", 1, true) then
	error("invalid CI component entry", 0)
end
if event ~= "push" and event ~= "pull_request" and event ~= "workflow_dispatch" then
	error("invalid CI event", 0)
end

local modulePath = "../../" .. entry:gsub("/init%.luau$", ""):gsub("%.luau$", "")
local implementation = require(modulePath)
if type(implementation) ~= "function" then
	error("CI component must return a callable function: " .. entry, 0)
end

implementation({ event = event })
