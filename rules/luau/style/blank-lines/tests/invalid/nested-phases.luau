local function selectPaths(paths: { string }): { string }
	if #paths == 0 then
		return {}
	end
	for index, path in paths do
		if path:find("\\", 1, true) then
			paths[index] = path:gsub("\\", "/")
		end
	end
	local first = paths[1]
	local rest = table.clone(paths)
	return if first then rest else {}
end

return selectPaths
