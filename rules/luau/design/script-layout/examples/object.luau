-- rules/luau/design/script-layout/examples/object.luau
--!strict

-- Sections: Modules → Types → Constants → Helpers → Functions → Constructor → Methods.

local Counter = {}
Counter.__index = Counter

--# Types

type Counter = setmetatable<{ count: number }, typeof(Counter)>

--# Constructor

--- Allocate independent state for one counter.
function Counter.new(): Counter
	return setmetatable({ count = 0 }, Counter)
end

--# Methods

--- Read this instance's count without changing it.
function Counter.Read(self: Counter): number
	return self.count
end

return Counter
