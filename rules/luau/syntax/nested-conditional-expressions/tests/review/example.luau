return function(ready: boolean, cached: boolean, choose: (string) -> string): string
	return if ready then choose(if cached then "cached" else "fresh") else "idle"
end
