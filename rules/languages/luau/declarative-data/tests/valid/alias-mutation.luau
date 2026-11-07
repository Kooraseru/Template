-- global-rules/languages/luau/declarative-data/tests/valid/alias-mutation.luau
--!strict

const active: { [string]: boolean } = { ready = false }
const alias = active

local function Update(id: string): ()
	alias[id] = true
end

return Update
