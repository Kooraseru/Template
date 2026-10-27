-- ci/components/pages/staticAssetCopier.luau
--!strict

-- Copy a documentation asset without changing its relative site path.
local Fs = require("@lune/fs")

local StaticAssetCopier = {}
StaticAssetCopier.__index = StaticAssetCopier

export type StaticAssetCopier = setmetatable<{}, typeof(StaticAssetCopier)>

function StaticAssetCopier.new(): StaticAssetCopier
	return setmetatable({}, StaticAssetCopier)
end

function StaticAssetCopier.Copy(self: StaticAssetCopier, source: string, destination: string): ()
	Fs.copy(source, destination)
end

return StaticAssetCopier
