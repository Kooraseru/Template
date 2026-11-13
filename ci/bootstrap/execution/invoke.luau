-- ci/bootstrap/execution/invoke.luau
--!strict

local Process = require("@lute/process")
local Fs = require("@std/fs")
local Toml = require("@formats/toml")
local Outcome = require("@ci/bootstrap/outcomes/outcome")
local Contract = require("@ci/bootstrap/contracts/contract")

const COMPONENTS_MODULE_PREFIX = "@ci/components"

type ComponentInstance = {
	Run: (self: ComponentInstance, context: { event: string }) -> unknown,
}

type ComponentClass = {
	new: () -> ComponentInstance,
}

-- The trusted coordinator inspects component contracts without executing them.
local entry = Process.args[2]
local event = Process.args[3]
if not entry then
	error("invalid CI component entry", 0)
end

if event ~= "push" and event ~= "pull_request" and event ~= "workflow_dispatch" then
	error("invalid CI event", 0)
end

local prefix = Contract.ComponentRoot .. "/"
local relative = if entry:sub(1, #prefix) == prefix then entry:sub(#prefix + 1) else ""
local moduleIdentity = relative:match("^(.+)/init%.luau$")
local commandIdentity = relative:match("^(.+)/component%.toml$")
local identity = moduleIdentity or commandIdentity
if not identity or not Contract.ValidIdentity(identity) then
	error("invalid CI component identity", 0)
end

if commandIdentity then
	-- Plain commands use the *same* validated component manifest and process boundary
	-- as module-backed tasks. No shell interpolation or additional entry script.
	local source = Toml.decode(Fs.readFileToString(entry))
	local component = Contract.new(identity, entry, entry, source)
	local command = component.command
	if not command then error(`{entry}: missing declarative command`, 0) end
	local result = Process.run(command, { cwd = Process.cwd(), stdio = "inherit" })
	local outcome = Outcome.FromExitCode(result.exitcode)
	if outcome == "failed" then Process.exit(1) end
	if outcome == "skipped" then Process.exit(Outcome.skippedExitCode) end
else
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

	local outcome = Outcome.FromReturn(instance:Run({ event = event }))
	if outcome == "skipped" then
		Process.exit(Outcome.skippedExitCode)
	end
end
