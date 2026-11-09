-- rules/luau/design/script-layout/examples/table-module.luau
--!strict

-- Sections: Modules → Types → Constants → Variables → Helpers → Functions.

local Counters = {}

--# Variables

local completed = 0

--# Functions

--- Track one completed job for this module's lifetime.
function Counters.Record(): ()
	completed += 1
end

return Counters
