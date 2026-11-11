-- source/hosts/windows-arm64/init.luau
--!strict

-- Host-specific build entry. This implementation owns its compiler and image.
local Process = require("@lute/process")
local Fs = require("@std/fs")

local DOCKER_OPTIONS: Process.ProcessRunOptions = { stdio = "inherit" }
const IMAGE = "template-windows-arm64"
const COMPILER = "aarch64-w64-mingw32-clang"
const OUTPUT = "build/artifacts/application/windows-arm64.exe"

local function runDocker(arguments: { string }): Process.ProcessResult
	local result = Process.run({ "docker", table.unpack(arguments) }, DOCKER_OPTIONS)
	if not result.ok then
		error(`Docker command failed with status {result.exitcode}`, 0)
	end
	return result
end

local Host = {}

function Host.Build(): ()
	Fs.createDirectory("build/artifacts/application", { makeParents = true })
	runDocker({
		"build",
		"--file",
		"source/hosts/windows-arm64/Dockerfile",
		"--tag",
		IMAGE,
		".",
	})
	local created = Process.run({
		"docker",
		"create",
		IMAGE,
		COMPILER,
		"-O2",
		'-DHOST_MESSAGE="Windows 11 ARM64"',
		"source/main.c",
		"-o",
		"/tmp/windows-arm64.exe",
	})
	if not created.ok then
		error(`Docker container creation failed with status {created.exitcode}`, 0)
	end
	local containerId = created.stdout:match("%S+")
	if not containerId then
		error("Docker did not return the ARM64 build container ID", 0)
	end
	runDocker({ "start", "--attach", containerId })
	runDocker({ "cp", `{containerId}:/tmp/windows-arm64.exe`, OUTPUT })
	runDocker({ "rm", containerId })
end

return Host
