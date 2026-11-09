local Counter = {}
Counter.__index = Counter

--# Constants

function Counter.Read(self: { count: number }): number
	return self.count
end

--# Constructor

function Counter.new()
	return setmetatable({ count = 0 }, Counter)
end

return Counter
