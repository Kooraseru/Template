return function(ready: boolean, cached: boolean, busy: boolean): string
	local result = if ready then (if cached then "cached" else "fresh") elseif busy then "wait" else "idle"
	return result
end
