-- rules/luau/design/script-layout/examples/function-module.luau
--!strict

-- Sections: Modules → Types → Constants → Helpers → Functions.

--# Functions

--- Clamp negative input before it reaches a counter.
return function(value: number): number
	return math.max(0, value)
end
