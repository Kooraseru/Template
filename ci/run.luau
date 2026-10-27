-- ci/run.luau
--!strict

local Fs = require("@lune/fs")
local Process = require("@lune/process")

type Executables = { [string]: string }

const EXECUTABLES: Executables = {
	["--windows-amd"] = "build/windows-amd.exe",
	["--windows-arm64"] = "build/windows-arm64.exe",
	["--windows-intel"] = "build/windows-intel.exe",
}

local variant = Process.args[1]
if variant == "--" then
	variant = Process.args[2]
end
if not variant or not EXECUTABLES[variant] then
	error("usage: bash ci/toolchain/lune.sh run ci/run.luau --windows-amd|--windows-arm64|--windows-intel", 0)
end

local executable = EXECUTABLES[variant]
if not Fs.isFile(executable) then
	error(`missing {executable}; build first with CI_EVENT=workflow_dispatch bash ci/toolchain/lune.sh run ci/entry.luau`, 0)
end

local options: Process.ExecOptions = {
	cwd = Process.cwd,
	stdio = "inherit",
}
local result = Process.exec(executable, {}, options)
if not result.ok then
	Process.exit(result.code)
end
