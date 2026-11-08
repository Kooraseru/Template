local tostring = tostring
tostring = function(value: unknown): string
	return if value then "yes" else "no"
end
return `{tostring(true)}`
