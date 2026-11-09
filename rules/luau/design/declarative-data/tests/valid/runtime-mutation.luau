-- global-rules/languages/luau/declarative-data/tests/valid/runtime-mutation.luau
--!strict

const active = {}

local function Register(id: string): ()
	active[id] = true
end

local function Unregister(id: string): ()
	active[id] = nil
end

Register("alpha")
Unregister("alpha")

return active
