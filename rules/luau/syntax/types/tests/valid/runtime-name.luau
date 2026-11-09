-- global-rules/languages/luau/language/types/tests/valid/runtime-name.luau
--!strict

const any = "the name of a runtime variable"
const message = "any also appears in this literal"

return any .. message
