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
local Releases = require("../../publication/releases/cli")
local Serde = require("@lune/serde")

--# Helpers

local function execute(input: boolean): boolean
	if not input then
		local previous = {
			ACT = Process.env.ACT,
			CI_TESTED_SHA = Process.env.CI_TESTED_SHA,
			CI_BUILD_SPEC = Process.env.CI_BUILD_SPEC,
			GITHUB_OUTPUT = Process.env.GITHUB_OUTPUT,
		}
		local output = "build/tests/worktree-preparation.env"
		local sha = Commands.Run("git", { "rev-parse", "HEAD" }):gsub("%s+$", "")
		Fs.writeDir("build/tests")
		Fs.writeFile(output, "")
		Process.env.ACT = "true"
		Process.env.CI_TESTED_SHA = sha
		Process.env.CI_BUILD_SPEC = Serde.encode("json", { source_sha = sha, cache_run = "" })
		Process.env.GITHUB_OUTPUT = output
		local ok, failure = pcall(Releases.Prepare)
		Process.env.ACT = previous.ACT
		Process.env.CI_TESTED_SHA = previous.CI_TESTED_SHA
		Process.env.CI_BUILD_SPEC = previous.CI_BUILD_SPEC
		Process.env.GITHUB_OUTPUT = previous.GITHUB_OUTPUT
		assert(ok, tostring(failure))
		assert(Fs.readFile(output):find("source_dir=" .. Process.cwd, 1, true), "local preparation discarded worktree")
		return true
	end
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
	Cases = {
		{ Name = "Resolve a relative executable inside the selected checkout", Input = true, Expected = true },
		{ Name = "Local selected source uses current worktree", Input = false, Expected = true },
	},
}

return Test.new(definition)
