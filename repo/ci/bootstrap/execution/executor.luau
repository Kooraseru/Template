-- repo/ci/bootstrap/execution/executor.luau
--!strict

local Fs = require("@lune/fs")
local Process = require("@lune/process")
local DateTime = require("@lune/datetime")
local Glob = require("@ci/bootstrap/discovery/glob")
local Contract = require("@ci/bootstrap/contracts/contract")
local Outcome = require("@ci/bootstrap/outcomes/outcome")
local SkipPolicy = require("@ci/bootstrap/outcomes/skipPolicy")
local Credentials = require("@ci/github/authentication/credentials")

local Executor = {}
Executor.__index = Executor

type Outcomes = { [string]: string }

type Fields = { credentials: Credentials.Credentials? }
export type Executor = setmetatable<Fields, typeof(Executor)>

export type Result = {
	outcomes: Outcomes,
	passed: boolean,
}

function Executor.new(credentials: Credentials.Credentials?): Executor
	local fields: Fields = { credentials = credentials }
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

function Executor.Invoke(self: Executor, task: Contract.Task, event: string): Outcome.Value
	local luneExecutable = Process.env.CI_LUNE
	if not luneExecutable then
		print("::error::CI_LUNE is unset; start CI with bash dependencies/lune/bootstrap.sh run repo/ci/entry.luau")
		return "failed"
	end
	local environment: { [string]: string } =
		{ GH_TOKEN = if task.boundary == "privileged" then Process.env.GH_TOKEN or "" else "" }
	environment.CI_COMPONENT = task.identity
	if self.credentials and task.boundary == "privileged" then
		for name, value in self.credentials:Environment(task.credentials) do
			environment[name] = value
		end
	end
	local options: Process.ExecOptions = {
		cwd = Process.cwd,
		stdio = "inherit",
		env = environment,
	}
	local ok, result = xpcall(Process.exec, tostring, luneExecutable, {
		"run",
		task.invoker,
		task.entry,
		event,
	}, options)

	if not ok then
		print(`::error::{task.identity}: unable to start Lune: {result}`)
		return "failed"
	end
	local outcome = Outcome.FromExitCode(result.code)
	if outcome == "failed" then
		print(`::error::{task.identity}: exited with status {result.code}`)
	end
	return outcome
end

function Executor.Execute(self: Executor, tasks: { Contract.Task }, event: string): Result
	local outcomes: Outcomes = {}
	local passed = true
	for _, task in tasks do
		local skipConclusion = SkipPolicy.Conclusion(task.identity)
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
			print(`::notice::Starting {task.identity} at {DateTime.now():toRfc3339()}`)
			local executed = self:Invoke(task, event)
			local missing = if executed == "passed" then self:MissingOutputs(task.outputs) else {}
			if #missing > 0 then
				print(`::error::{task.identity}: missing declared outputs {table.concat(missing, ", ")}`)
			end
			outcome = if #missing > 0 then "failed" else executed
		end
		print(`::notice::{task.identity}: {outcome} at {DateTime.now():toRfc3339()}`)
		print("::endgroup::")

		outcomes[task.identity] = outcome
		local neutralReported = true
		if outcome == "skipped" and skipConclusion == "neutral" then
			local ok, failure = xpcall(function(): string
				SkipPolicy.ReportNeutral(task.identity, self.credentials)
				return "reported"
			end, tostring)
			if not ok then
				neutralReported = false
				print(`::error::{task.identity}: unable to report neutral Check Run: {failure}`)
			end
		end
		if
			outcome == "failed"
			or outcome == "blocked"
			or (outcome == "skipped" and skipConclusion == "failure")
			or not neutralReported
		then
			passed = false
			if outcome == "skipped" and skipConclusion == "neutral" and not neutralReported then
				outcomes[task.identity] = "skipped (neutral Check Run failed)"
			end
			if outcome == "skipped" then
				if skipConclusion == "failure" then
					print(
						`::error::{task.identity}: component outcome is skipped; configured job conclusion is failure`
					)
				end
			end
		end
	end
	return { outcomes = outcomes, passed = passed }
end

return Executor
