local External = require("../External")

type Result = External.foreignType
return function(value: Result): Result
	return value
end
