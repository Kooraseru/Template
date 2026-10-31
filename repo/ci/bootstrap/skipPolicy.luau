-- repo/ci/bootstrap/skipPolicy.luau
--!strict

local Fs = require("@lune/fs")
local Serde = require("@lune/serde")

local SkipPolicy = {}

local function record(value: unknown): { [string]: unknown }
	if type(value) ~= "table" then
		error("CI execution settings must be TOML tables", 0)
	end
	local result: { [string]: unknown } = {}
	for key, item in value do
		if type(key) ~= "string" then
			error("CI execution setting names must be strings", 0)
		end
		result[key] = item
	end
	return result
end

function SkipPolicy.Conclusion(identity: string): string
	local decoded = record(Serde.decode("toml", Fs.readFile("repo/config/ci/execution.toml")))
	for field in decoded do
		if field ~= "skip" then
			error(`Unknown CI execution setting {tostring(field)}`, 0)
		end
	end
	local settings = record(decoded.skip)
	for field in settings do
		if field ~= "default" and field ~= "components" then
			error(`Unknown CI skip setting {tostring(field)}`, 0)
		end
	end
	if settings.default ~= "success" and settings.default ~= "failure" then
		error("skip.default must be success or failure for the native Actions backend", 0)
	end
	local overrides = record(settings.components)
	for name, value in overrides do
		if type(name) ~= "string" or not name:match("^[a-z][a-z0-9_-]*$") then
			error("Invalid skip component identity", 0)
		end
		if value ~= "success" and value ~= "failure" then
			error(`skip.components.{name} must be success or failure for the native Actions backend`, 0)
		end
	end
	local conclusion = overrides[identity]
	if type(conclusion) ~= "string" then
		conclusion = settings.default
	end
	return conclusion :: string
end

return SkipPolicy
