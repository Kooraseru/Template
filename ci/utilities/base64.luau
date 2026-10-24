-- ci/utilities/base64.luau
--!strict

local Base64 = {}

--# Constants

local ALPHABET = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"

--# Functions

function Base64.Encode(bytes: string): string
	local output = {}

	for offset = 1, #bytes, 3 do
		local a, b, c = bytes:byte(offset, offset + 2)
		local value = a * 65536 + (b or 0) * 256 + (c or 0)

		for index = 0, 3 do
			local digit = math.floor(value / 2 ^ (18 - index * 6)) % 64
			table.insert(output, if index > #bytes - offset + 1 then "=" else ALPHABET:sub(digit + 1, digit + 1))
		end
	end

	return table.concat(output)
end

function Base64.Decode(encoded: string): string
	local text = encoded:gsub("%s", "")
	assert(#text % 4 == 0, "Invalid base64 length")
	local output = {}

	for offset = 1, #text, 4 do
		local value = 0
		local padding = 0

		for index = 0, 3 do
			local character = text:sub(offset + index, offset + index)

			if character == "=" then
				assert(offset + 3 == #text and index >= 2, "Invalid base64 padding")
				padding += 1
				value *= 64
			else
				local digit = ALPHABET:find(character, 1, true)
				assert(digit and padding == 0, "Invalid base64 character")
				value = value * 64 + digit - 1
			end
		end

		for index = 0, 2 - padding do
			table.insert(output, string.char(math.floor(value / 2 ^ (16 - index * 8)) % 256))
		end
	end

	return table.concat(output)
end

return Base64
