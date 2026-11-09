--!strict

local function run(value: string?): string?
	if value then
		print(value)
	else
		return nil
	end
	return value
end

return run
