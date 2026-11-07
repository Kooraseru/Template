-- global-rules/languages/luau/declarative-data/tests/valid/computed-initializer.luau
--!strict

local function Compute(): string
	return tostring(os.clock())
end

const values = { updatedAt = Compute() }
return values
