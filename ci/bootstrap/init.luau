-- ci/bootstrap/init.luau
--!strict

-- Trusted CI entry: discover source contracts, resolve dependency order,
-- execute only compatible components, and report their actual outcomes.

local Fs = require("@lune/fs")
local Process = require("@lune/process")

local Component = require("./component")
local Contracts = require("./contracts")
local Planning = require("./planning")
local Glob = require("./glob")

type Task = Component.Task

local function missingOutputs(outputs: { string }): { string }
	local missing = {}
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

-- Implementation code is invoked only after every discovered static contract
-- has passed validation. Each component gets a fresh Lune process, preventing
-- cross-component module cache or global state from leaking into other tasks.
local function invoke(task: Task, event: string): boolean
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

local function execute(tasks: { Task }, event: string, outcomes: { [string]: string }): boolean
	local passed = true
	for _, task in tasks do
		local blockedBy = {}
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
			local executed = invoke(task, event)
			local missing = if executed then missingOutputs(task.outputs) else {}
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
	return passed
end

local function summarize(outcomes: { [string]: string }, validators: number, workers: number)
	local summary = {
		"## CI bootstrap",
		"",
		`Discovered {validators} validation components and {workers} work components.`,
		"",
		"| Component | Outcome |",
		"| --- | --- |",
	}
	local identities = {}
	for identity in outcomes do
		table.insert(identities, identity)
	end
	table.sort(identities)
	for _, identity in identities do
		table.insert(summary, `| {identity} | {outcomes[identity]} |`)
	end
	if #identities == 0 then
		table.insert(summary, "| — | No components were discovered |")
	end
	local text = table.concat(summary, "\n") .. "\n"
	print(text)

	local destination = Process.env.GITHUB_STEP_SUMMARY
	if destination then
		local current = if Fs.isFile(destination) then Fs.readFile(destination) else ""
		Fs.writeFile(destination, current .. text)
	end
end

local function bootstrap()
	local event = Process.env.CI_EVENT
	if not event then
		error("CI_EVENT is required", 0)
	end

	local validators, workers = Planning.Resolve(Contracts.Discover(), event)
	local outcomes: { [string]: string } = {}

	print(`CI selected {#validators} validation components and {#workers} work components`)
	local valid = execute(validators, event, outcomes)
	if not valid then
		summarize(outcomes, #validators, #workers)
		error("planning validation failed; work was not executed", 0)
	end

	local completed = execute(workers, event, outcomes)
	summarize(outcomes, #validators, #workers)
	if not completed then
		error("one or more discovered CI components failed or were blocked", 0)
	end
end

local ok, problem = pcall(bootstrap)
if not ok then
	warn(`::error::{problem}`)
	Process.exit(1)
end
