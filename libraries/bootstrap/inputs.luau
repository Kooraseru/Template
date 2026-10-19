-- libraries/bootstrap/inputs.luau
--!strict

local Inputs = {}

--# Modules

local Fs = require("@lune/fs")
local Process = require("@lune/process")
-- One process-wide source selection; temporary selectors must restore the previous ref.
Inputs.ref = Process.env.CI_INPUT_REF or ""

--# Functions

function Inputs.LegacyPath(path: string): string
	if path == "config/project.toml" then
		return "ci/config.toml"
	end

	if path == "fabricator/targets.json" then
		return "ci/build/targets.json"
	end

	local prefix = "fabricator/distribution/images/"

	if path:sub(1, #prefix) == prefix then
		return "ci/images/" .. path:sub(#prefix + 1)
	end

	return path
end

function Inputs.Read(path: string): string

	if Inputs.ref == "" then
		return Fs.readFile(path)
	end

	local result = Process.exec("git", { "show", Inputs.ref .. ":" .. path })
	local legacy = Inputs.LegacyPath(path)

	if not result.ok and legacy ~= path then
		result = Process.exec("git", { "show", Inputs.ref .. ":" .. legacy })
	end

	assert(result.ok, "missing selected commit input: " .. path .. "\n" .. result.stderr)

	return result.stdout
end

return Inputs
