local function inspect(value: unknown, read: () -> string)
	return `{tostring(value)} {read()}`, `{tostring(read())}`
end
return inspect
