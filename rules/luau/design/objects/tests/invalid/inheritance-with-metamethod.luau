const Base = {}
const Derived = {}
function Base.new()
	return setmetatable({}, Base)
end
function Derived.new()
	return setmetatable({}, Derived)
end
setmetatable(Derived, { __index = Base, __tostring = function() return "Derived" end })
return Derived
