-- rules/luau/design/script-layout/examples/entry-point.luau
--!strict

-- Sections: Modules → Types → Constants → Helpers → Initialization.

--# Helpers

--- Start the application after the entry point has finished loading.
local function start(): ()
	print("Ready")
end

--# Initialization

start()
