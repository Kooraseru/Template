--[[
	Classifies known response codes before falling back to an unknown result.

	@param response number HTTP status from the server.
]]
local function classify(status: number): string
	if status == 401 then
		return "authentication"
	end

	if status == 403 then
		return "permission"
	end

	if status == 404 then
		return "missing"
	end

	return "unknown"
end

return classify
