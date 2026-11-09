local function run(ready: boolean, done: boolean): boolean?
	if ready then
		return true
	end
	if done then
		return false
	end
	return nil
end

return run
