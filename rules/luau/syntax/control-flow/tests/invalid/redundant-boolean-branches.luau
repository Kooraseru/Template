local function compare(left: number, right: number, label: string?): (boolean, boolean)
	return if left >= right then true else false, if label then false else true
end

return compare
