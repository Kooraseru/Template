local runtimePath = "./Render"
local runtimeModule = require(runtimePath)

local function require(path: string): string
	return path
end

local customValue = require("plain text")
return runtimeModule, customValue
