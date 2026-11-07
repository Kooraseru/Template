-- dependencies/packages/dataFormats/hash.luau
--!strict
local Crypto = require("@lute/crypto")
local function sha256(input: string): string
 local digest = Crypto.digest(Crypto.hash.sha256, input)
 local parts: { string } = {}
 for index = 0, buffer.len(digest) - 1 do
  table.insert(parts, string.format("%02x", buffer.readu8(digest, index)))
 end
 return table.concat(parts)
end
return { sha256 = sha256 }
