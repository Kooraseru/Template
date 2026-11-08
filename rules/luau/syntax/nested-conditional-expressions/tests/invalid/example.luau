local result = if ready then (if cached then "cached" else "fresh") elseif busy then "wait" else "idle"
return result
