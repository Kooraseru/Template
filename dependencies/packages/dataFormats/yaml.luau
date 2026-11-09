-- dependencies/packages/dataFormats/yaml.luau
--!strict
local Process = require("@lute/process")
local Json = require("./json")
local function decode(input: string): unknown
	local result = Process.run({ "node", "dependencies/packages/dataFormats/parse.mjs", "yaml", input })
	if not result.ok then error(`Unable to decode yaml: {result.stderr}`, 0) end
	return Json.decode(result.stdout)
end
return { decode = decode, encode = Json.encode }
