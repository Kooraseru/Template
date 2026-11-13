--!strict
-- An ordinary discovered validation component. Diagnostics retain their own namespace.
local Fs = require("@std/fs")
local Process = require("@lute/process")

local Component = {}
Component.__index = Component

function Component.new()
	return setmetatable({}, Component)
end

function Component.Run(_self, _context: { event: string }): ()
	local result = Process.run({ "node", "ci/rules-audit.cjs" }, { cwd = Process.cwd(), stdio = "inherit" })
	if not result.ok then
		error("rules-audit reported blocking findings or an execution error", 0)
	end
	local destination = "build/artifacts/quality/rules-audit"
	Fs.createDirectory(destination, { makeParents = true })
	local copied = Process.run({ "cp", "-a", "build/rules-audit/.", destination .. "/" })
	if not copied.ok then error("Unable to preserve rules-audit diagnostic artifacts", 0) end
end

return Component
