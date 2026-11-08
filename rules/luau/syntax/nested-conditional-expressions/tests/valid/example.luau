return function(ready: boolean, busy: boolean): string
	local result = if ready then "ready" elseif busy then "wait" else "idle"
	return result
end
