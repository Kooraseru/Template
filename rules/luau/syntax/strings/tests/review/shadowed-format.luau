local string = { format = function(_format, value)
	return value
end }
return string.format("%s", "ready")
