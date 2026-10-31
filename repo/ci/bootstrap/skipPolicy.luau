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

function SkipPolicy.Reject(identity: string): boolean
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
	if settings.default ~= "allow" and settings.default ~= "fail" then
		error("skip.default must be allow or fail", 0)
	end
	local overrides = record(settings.components)
	for name, value in overrides do
		if type(name) ~= "string" or not name:match("^[a-z][a-z0-9_-]*$") then
			error("Invalid skip component identity", 0)
		end
		if value ~= "allow" and value ~= "fail" then
			error(`skip.components.{name} must be allow or fail`, 0)
		end
	end
	return (overrides[identity] or settings.default) == "fail"
end

return SkipPolicy
