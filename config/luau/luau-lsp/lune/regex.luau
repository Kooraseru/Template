--!strict

export type Pattern = { isMatch: (self: Pattern, text: string) -> boolean }

local Regex = {} :: { new: (pattern: string) -> Pattern }

return Regex
