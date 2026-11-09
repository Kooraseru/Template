-- source/hosts/windows-amd/init.luau
--!strict

-- The AMD host controls its own toolchain and output.
local Process = require("@lute/process")
local Fs = require("@std/fs")

local DOCKER_OPTIONS: Process.ProcessRunOptions = { stdio = "inherit" }
const IMAGE = "template-windows-amd"
const COMPILER = "x86_64-w64-mingw32-clang"
const OUTPUT = "build/run/ci-execution/artifacts/application/windows-amd.exe"

local function runDocker(arguments: { string }): Process.ProcessResult
	local result = Process.run({ "docker", table.unpack(arguments) }, DOCKER_OPTIONS)
	if not result.ok then
		error(`Docker command failed with status {result.exitcode}`, 0)
	end
	return result
end

local Host = {}

function Host.Build(): ()
	Fs.createDirectory("build/run/ci-execution/artifacts/application", { makeParents = true })
	runDocker({
		"build",
		"--file",
		"source/hosts/windows-amd/Dockerfile",
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
		'-DHOST_MESSAGE="Windows 11 x86-64 AMD"',
		"source/main.c",
		"-o",
		"/tmp/windows-amd.exe",
	})
	if not created.ok then
		error(`Docker container creation failed with status {created.exitcode}`, 0)
	end
	local containerId = created.stdout:match("%S+")
	if not containerId then
		error("Docker did not return the AMD build container ID", 0)
	end
	runDocker({ "start", "--attach", containerId })
	runDocker({ "cp", `{containerId}:/tmp/windows-amd.exe`, OUTPUT })
	runDocker({ "rm", containerId })
end

return Host
