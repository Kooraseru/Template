-- ci/utilities/bytes.luau
--!strict

local Bytes = {}

--# Functions

function Bytes.Hex(bytes: string): string
	return (bytes:gsub(".", function(character)
		return string.format("%02x", character:byte())
	end))
end

function Bytes.FromHex(text: string): string
	assert(#text % 2 == 0 and (text == "" or text:match("^%x+$")), "invalid hexadecimal bytes")

	return (text:gsub("..", function(pair)
		return string.char(assert(tonumber(pair, 16)))
	end))
end

return Bytes
