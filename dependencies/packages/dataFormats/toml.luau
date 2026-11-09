-- dependencies/packages/dataFormats/toml.luau
--!strict
local Process = require("@lute/process")
local Json = require("./json")
local function decode(input: string): unknown
	local result = Process.run({ "node", "dependencies/packages/dataFormats/parse.mjs", "toml", input })
	if not result.ok then error(`Unable to decode toml: {result.stderr}`, 0) end
	return Json.decode(result.stdout)
end
return { decode = decode }
