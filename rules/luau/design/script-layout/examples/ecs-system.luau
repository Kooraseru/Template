-- rules/luau/design/script-layout/examples/ecs-system.luau
--!strict

-- Sections: Modules → Types → Constants → Helpers → Functions.

--# Types

type Position = { x: number, y: number }

--# Functions

--- Apply a step to the positions selected by the caller's query.
return function(positions: { Position }, step: number): ()
	for _, position in positions do
		position.x += step
	end
end
