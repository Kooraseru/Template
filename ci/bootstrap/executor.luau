-- ci/bootstrap/executor.luau
--!strict

local Fs = require("@lune/fs")
local Process = require("@lune/process")
local Glob = require("./glob")
local Contract = require("./contract")

local Executor = {}
Executor.__index = Executor

type Outcomes = { [string]: string }

export type Executor = setmetatable<{}, typeof(Executor)>

export type Result = {
	outcomes: Outcomes,
	passed: boolean,
}

function Executor.new(): Executor
	local fields = {}
	return setmetatable(fields, Executor)
end

function Executor.MissingOutputs(self: Executor, outputs: { string }): { string }
	local missing: { string } = {}
	for _, pattern in outputs do
		if pattern:find("*", 1, true) or pattern:find("?", 1, true) then
			if #Glob.Find(pattern) == 0 then
				table.insert(missing, pattern)
			end
		elseif not Fs.metadata(pattern).exists then
			table.insert(missing, pattern)
		end
	end
	return missing
end

function Executor.Invoke(self: Executor, task: Contract.Task, event: string): boolean
	local luneExecutable = Process.env.CI_LUNE
	if not luneExecutable then
		print("::error::CI_LUNE is unset; start CI with bash ci/toolchain/lune.sh run ci/entry.luau")
		return false
	end
	local options: Process.ExecOptions = {
		cwd = Process.cwd,
		stdio = "inherit",
	}
	local ok, result = xpcall(Process.exec, tostring, luneExecutable, {
		"run",
		task.invoker,
		task.entry,
		event,
	}, options)

	if not ok then
		print(`::error::{task.identity}: unable to start Lune: {result}`)
		return false
	end
	if not result.ok then
		print(`::error::{task.identity}: exited with status {result.code}`)
	end
	return result.ok
end

function Executor.Execute(self: Executor, tasks: { Contract.Task }, event: string): Result
	local outcomes: Outcomes = {}
	local passed = true
	for _, task in tasks do
		local blockedBy: { string } = {}
		for _, dependency in task.needs do
			if outcomes[dependency] ~= "passed" then
				table.insert(blockedBy, dependency)
			end
		end

		print(`::group::{task.identity}`)
		local outcome: string
		if #blockedBy > 0 then
			outcome = "blocked"
			print(`::error::{task.identity}: blocked by {table.concat(blockedBy, ", ")}`)
		else
			local executed = self:Invoke(task, event)
			local missing = if executed then self:MissingOutputs(task.outputs) else {}
			if #missing > 0 then
				print(`::error::{task.identity}: missing declared outputs {table.concat(missing, ", ")}`)
			end
			outcome = if executed and #missing == 0 then "passed" else "failed"
		end
		print("::endgroup::")

		outcomes[task.identity] = outcome
		if outcome ~= "passed" then
			passed = false
		end
	end
	return { outcomes = outcomes, passed = passed }
end

return Executor
