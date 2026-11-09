-- global-rules/languages/luau/language/types/tests/invalid/nested-any.luau
--!strict

type Payload = { value: any }
type Callback = (string) -> any

return nil
