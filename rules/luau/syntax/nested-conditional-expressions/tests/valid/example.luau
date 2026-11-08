local result = if ready then "ready" elseif busy then "wait" else "idle"
return result
