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
