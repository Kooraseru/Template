-- repo/ci/entry.luau
--!strict

local Bootstrap = require("./bootstrap")
local Process = require("@lune/process")

local argumentIndex = if Process.args[1] == "--" then 2 else 1
local argument = Process.args[argumentIndex]
local preflightOnly = argument == "--preflight-only"
local component = if argument == "--component" then Process.args[argumentIndex + 1] else nil
local reportOnly = argument == "--report"
if argument and not preflightOnly and not component and not reportOnly then
	error("expected --preflight-only, --component <identity>, --report, or no arguments", 0)
end
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
	Bootstrap.new(event):Run(preflightOnly, component, reportOnly)
	return true
end, tostring)
if not ok then
	print(`::error::{problem}`)
	Process.exit(1)
end
