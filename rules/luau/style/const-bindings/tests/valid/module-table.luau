-- rules/luau/style/const-bindings/tests/valid/module-table.luau
--!strict

local Glob = {}

--- Returns the first path segment.
function Glob.First(path: string): string
	local segments = path:split("/")
	return segments[1]
end

return Glob
