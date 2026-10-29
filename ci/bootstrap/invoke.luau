-- ci/bootstrap/invoke.luau
--!strict

local Process = require("@lune/process")

const COMPONENTS_MODULE_PREFIX = "../../ci/components"

type ComponentInstance = {
	Run: (self: ComponentInstance, context: { event: string }) -> (),
}

type ComponentClass = {
	new: () -> ComponentInstance,
}

-- The trusted coordinator inspects component contracts without executing them.
local entry = Process.args[1]
local event = Process.args[2]
if not entry or not entry:match("^ci/components/[%w_-]+/init%.luau$") then
	error("invalid CI component entry", 0)
end
if event ~= "push" and event ~= "pull_request" and event ~= "workflow_dispatch" then
	error("invalid CI event", 0)
end

local identity = entry:match("^ci/components/([%w_-]+)/init%.luau$")
if not identity then
	error("invalid CI component identity", 0)
end

local modulePath = `{COMPONENTS_MODULE_PREFIX}/{identity}`
local loaded, implementation = xpcall(require, tostring, modulePath)
if not loaded then
	error(`CI component failed to load: {implementation}`, 0)
end
if type(implementation) ~= "table" or type(implementation.new) ~= "function" then
	error(`CI component must expose a class constructor: {entry}`, 0)
end

local componentClass: ComponentClass = implementation
local instance = componentClass.new()
if type(instance) ~= "table" or type(instance.Run) ~= "function" then
	error(`CI component constructor must return an instance with Run: {entry}`, 0)
end

instance:Run({ event = event })
