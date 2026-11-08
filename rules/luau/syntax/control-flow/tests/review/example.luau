local function run(ready: boolean)
	if ready then
		local message = "ready"
		print(message)
	else
		return
	end
end
return run
