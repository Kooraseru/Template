--!strict

local function run(ready: boolean)
	if ready then
		print("ready")
	else
		error("missing input")
	end
end

return run
