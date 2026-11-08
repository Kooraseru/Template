--!strict
--# Functions
local function first() return true end
--# Functions
local function second() return first() end
return second
