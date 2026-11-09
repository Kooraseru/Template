local Fs = require("@std/fs")
local state = { ready = false }

local function check(): boolean
	state.ready = Fs.exists(".")
	return state.ready
end

return check
