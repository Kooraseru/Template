--!strict

local function run(ready: boolean)
	local function error(message: string)
		print(message)
	end
	if ready then
		print("ready")
	else
		error("missing input")
	end
end

return run
