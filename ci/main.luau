-- ci/main.luau
--!strict

local Bootstrap = require("./bootstrap")
local Process = require("@lune/process")

local event = Process.env.CI_EVENT
if not event then
	warn("::error::CI_EVENT is required")
	Process.exit(1)
end

local ok, problem = pcall(function()
	Bootstrap.new(event):Run()
end)
if not ok then
	warn(`::error::{problem}`)
	Process.exit(1)
end
