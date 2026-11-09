const Lookup = {}
const Defaults = {}
setmetatable(Lookup, { __index = Defaults })
return Lookup
