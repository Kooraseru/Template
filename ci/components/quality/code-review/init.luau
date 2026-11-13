--!strict
-- An ordinary discovered validation component. Diagnostics retain their own namespace.
local Process = require("@lute/process")

local Component = {}
Component.__index = Component

function Component.new()
	return setmetatable({}, Component)
end

function Component.Run(_self, _context: { event: string }): ()
	local result = Process.run({ "node", "ci/code-review.cjs" }, { cwd = Process.cwd(), stdio = "inherit" })
	if not result.ok then
		error("code-review reported blocking findings or an execution error", 0)
	end
end

return Component
