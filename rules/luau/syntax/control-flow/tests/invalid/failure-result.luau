--!strict

local function run(value: string?): (string?, string?)
	if value then
		print(value)
	else
		return nil, "missing input"
	end
	return value, nil
end

return run
