-- ci/fabricator/targets.luau
--!strict

local Targets = {}

--# Modules

local Fs = require("@lune/fs")
local Shape = require("../libraries/registry/shape")
local Inputs = require("../libraries/bootstrap/inputs")

--# Types

export type Target = { id: string, system: string, path: string }

--# Functions

function Targets.Validate(value: unknown): { Target }
	local result: { Target } = {}
	local seen: { [string]: boolean } = {}

	for _, raw in Shape.Sequence(value) do
		local entry = Shape.Object(raw, { "id", "system", "path" })
		local id = Shape.Text(entry.id, "target identifier")
		assert(id:match("^[%w][%w_-]*$"), "invalid target identifier: " .. id)
		local system = Shape.Text(entry.system, "build system")
		assert(system == "cargo" or system == "cmake", "unsupported build system: " .. system)
		assert(not seen[id], "duplicate build target: " .. id)
		seen[id] = true
		local path = if entry.path == "." then "." else Shape.Relative(entry.path)
		table.insert(result, { id = id, system = system, path = path })
	end

	return result
end

function Targets.Select(targets: { Target }, selected: { string }?): { Target }
	if not selected then
		return table.clone(targets)
	end

	local result: { Target } = {}
	local seen: { [string]: boolean } = {}

	for _, id in selected do
		assert(not seen[id], "duplicate target selection: " .. id)
		seen[id] = true
		local found: Target? = nil

		for _, target in targets do
			if target.id == id then
				found = target
				break
			end
		end

		assert(found, "unknown project target: " .. id)
		table.insert(result, found)
	end

	return result
end

function Targets.Discover(value: unknown): { Target }
	local targets = Targets.Validate(value)

	for _, target in targets do
		local manifest = if target.system == "cargo" then "Cargo.toml" else "CMakeLists.txt"
		Inputs.Read((if target.path == "." then "" else target.path .. "/") .. manifest)
	end

	return targets
end

function Targets.Commands(target: Target): { { string } }
	-- Validate caller-created entries as well as parsed project configuration.
	Targets.Validate({ target })

	if target.system == "cargo" then
		local options = { "cargo" }
		local configuration = target.path .. "/config.toml"
		if Fs.isFile(configuration) then
			table.insert(options, "--config")
			table.insert(options, configuration)
		end
		for _, argument in { "build", "--locked", "--release", "--manifest-path", target.path .. "/Cargo.toml" } do
			table.insert(options, argument)
		end
		return { options }
	end

	local directory = "build/targets/" .. target.id

	return {
		{ "cmake", "-S", target.path, "-B", directory, "-DCMAKE_BUILD_TYPE=Release" },
		{ "cmake", "--build", directory, "--config", "Release" },
	}
end

return Targets
