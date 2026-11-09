local Child = require("@self/Child")
local Surface = {}
function Surface.Run()
	return Child.Start()
end
return Surface
