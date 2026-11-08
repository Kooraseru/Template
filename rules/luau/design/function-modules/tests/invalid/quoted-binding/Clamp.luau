--!strict

local clamp = function(value: number): number return math.max(value, 0) end
return { ['Clamp'] = clamp }
