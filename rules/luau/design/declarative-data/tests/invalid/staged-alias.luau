-- global-rules/languages/luau/declarative-data/tests/invalid/staged-alias.luau
--!strict

const settings: { [string]: boolean } = { enabled = true }
const alias = settings

alias["retry"] = false

return settings
