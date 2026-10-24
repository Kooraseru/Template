-- ci/utilities/commands.luau
--!strict

local Commands = {}

--# Modules

local Process = require("@lune/process")
local Task = require("@lune/task")

--# Functions

function Commands.Execute(
	program: string,
	arguments: { string },
	input: string?,
	cwd: string?,
	env: { [string]: string }?
): Process.Execution
	if input == nil then
		return Process.exec(program, arguments, { cwd = cwd, env = env })
	end
	local child = Process.create(program, arguments, { cwd = cwd, env = env })
	Task.spawn(function()
		child.stdin:write(input)
		child.stdin:close()
	end)
	local stderr: string? = nil
	Task.spawn(function()
		stderr = child.stderr:readToEnd()
	end)
	local stdout = child.stdout:readToEnd()
	local status = child:status()
	while stderr == nil do
		Task.wait()
	end
	return { ok = status.ok, code = status.code, stdout = stdout, stderr = assert(stderr) }
end

function Commands.Run(
	program: string,
	arguments: { string },
	input: string?,
	cwd: string?,
	env: { [string]: string }?
): string
	local result = Commands.Execute(program, arguments, input, cwd, env)
	assert(result.ok, program .. " failed: " .. result.stderr)
	return result.stdout
end

return Commands
