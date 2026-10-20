-- fabricator/tests/checkout.luau
--!strict

local Test = require("@testing")

--# Modules

local Process = require("@lune/process")
local Fs = require("@lune/fs")
local Commands = require("../../libraries/bootstrap/commands")
local Files = require("../../libraries/bootstrap/files")
local Config = require("../../libraries/registry/config")
local Executor = require("../execute")

--# Helpers

local function execute(_input: boolean): boolean
	local root = "build/tests/native-checkout"
	Files.Reset(root)
	Fs.writeDir(root .. "/build")
	local installed = Commands.Run(if Process.os == "windows" then "where.exe" else "which", { "lune" })
		:match("[^\r\n]+")
	assert(installed, "cannot locate Lune executable")
	local name = "source-lune" .. (if Process.os == "windows" then ".exe" else "")
	Fs.copy(installed, root .. "/build/" .. name, true)
	if Process.os ~= "windows" then
		Commands.Run("chmod", { "755", root .. "/build/" .. name })
	end
	local config = Config.Read()
	config.build.commands = {}
	config.build.package_paths = {}
	config.targets = {}
	local previous = Process.env.CI_SOURCE_DIR
	Process.env.CI_SOURCE_DIR = Process.cwd:gsub("\\", "/"):gsub("/$", "") .. "/" .. root
	local target: Config.BuildEntry = {
		name = "native-checkout-fixture",
		runner = config.build.runner,
		probes = { { argv = { "build/" .. name, "--version" }, code = 0, stdout_contains = "lune" } },
	}
	local ok, failure = pcall(Executor.Run, config, target)
	Process.env.CI_SOURCE_DIR = previous
	assert(ok, tostring(failure))
	return true
end

--# Declaration

local definition: Test.Definition<boolean, boolean> = {
	Name = "Native programs in selected source checkouts",
	Execute = execute,
	Cases = { { Name = "Resolve a relative executable inside the selected checkout", Input = true, Expected = true } },
}

return Test.new(definition)
