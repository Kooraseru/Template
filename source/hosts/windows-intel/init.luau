-- source/hosts/windows-intel/init.luau
--!strict

-- The Intel host controls its own toolchain and output.
local Process = require("@lune/process")

const DOCKER_OPTIONS: Process.ExecOptions = { stdio = "inherit" }
const IMAGE = "template-windows-intel"
const COMPILER = "x86_64-w64-mingw32-clang"
const OUTPUT = "build/windows-intel.exe"

local function runDocker(arguments: { string }): Process.ExecResult
	local result = Process.exec("docker", arguments, DOCKER_OPTIONS)
	if not result.ok then
		error(`Docker command failed with status {result.code}`, 0)
	end
	return result
end

return function()
	runDocker({
		"build",
		"--file",
		"source/hosts/windows-intel/Dockerfile",
		"--tag",
		IMAGE,
		".",
	})
	local created = Process.exec("docker", {
		"create",
		IMAGE,
		COMPILER,
		"-O2",
		'-DHOST_MESSAGE="Windows 11 x86-64 Intel"',
		"source/main.c",
		"-o",
		"/tmp/windows-intel.exe",
	})
	if not created.ok then
		error(`Docker container creation failed with status {created.code}`, 0)
	end
	local containerId = created.stdout:match("%S+")
	if not containerId then
		error("Docker did not return the Intel build container ID", 0)
	end
	runDocker({ "start", "--attach", containerId })
	runDocker({ "cp", `{containerId}:/tmp/windows-intel.exe`, OUTPUT })
	runDocker({ "rm", containerId })
end
