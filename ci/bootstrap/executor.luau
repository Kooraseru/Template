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
	local ok, result = pcall(Process.exec, Process.env.CI_LUNE or "lune", {
		"run",
		"ci/bootstrap/invoke.luau",
		task.entry,
		event,
	}, { cwd = Process.cwd })

	if not ok then
		warn(`::error::{task.identity}: unable to start Lune: {result}`)
		return false
	end
	if result.stdout ~= "" then
		print(result.stdout)
	end
	if result.stderr ~= "" then
		warn(result.stderr)
	end
	if not result.ok then
		warn(`::error::{task.identity}: exited with status {result.code}`)
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
			warn(`::error::{task.identity}: blocked by {table.concat(blockedBy, ", ")}`)
		else
			local executed = self:Invoke(task, event)
			local missing = if executed then self:MissingOutputs(task.outputs) else {}
			if #missing > 0 then
				warn(`::error::{task.identity}: missing declared outputs {table.concat(missing, ", ")}`)
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
