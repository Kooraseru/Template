local count = 0
local service = require("@std/fs")

local function update(): ()
	count += 1
	service = require("@std/fs")
end

update()
return count, service
