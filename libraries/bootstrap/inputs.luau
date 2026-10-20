-- libraries/bootstrap/inputs.luau
--!strict

local Inputs = {}

--# Modules

local Fs = require("@lune/fs")
local Process = require("@lune/process")
-- One process-wide source selection; temporary selectors must restore the previous ref.
Inputs.ref = Process.env.CI_INPUT_REF or ""

--# Functions

function Inputs.Read(path: string): string

	if Inputs.ref == "" then
		return Fs.readFile(path)
	end

	local result = Process.exec("git", { "show", Inputs.ref .. ":" .. path })

	assert(result.ok, "missing selected commit input: " .. path .. "\n" .. result.stderr)

	return result.stdout
end

return Inputs
