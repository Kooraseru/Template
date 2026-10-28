-- ci/entry.luau
--!strict

local Bootstrap = require("./bootstrap")
local Process = require("@lune/process")

local argument = Process.args[1]
if argument == "--" then
	argument = Process.args[2]
end
local preflightOnly = argument == "--preflight-only"
local configuredEvent = Process.env.CI_EVENT
local event: string
if configuredEvent then
	event = configuredEvent
elseif preflightOnly then
	event = "workflow_dispatch"
else
	print("::error::CI_EVENT is required")
	return Process.exit(1)
end

local ok, problem = xpcall(function(): boolean
	Bootstrap.new(event):Run(preflightOnly)
	return true
end, tostring)
if not ok then
	print(`::error::{problem}`)
	Process.exit(1)
end
