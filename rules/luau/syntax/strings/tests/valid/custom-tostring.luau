local function tostring(value: boolean): string
	return if value then "yes" else "no"
end
return `{tostring(true)}`
