-- rules/languages/luau/language/types/tests/review/qualified-any.luau
--!strict

-- The rule cannot establish what a type exported by another module represents.
export type Imported = External.any
return true
