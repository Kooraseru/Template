-- repo/ci/github/taskRunner.luau
--!strict

local Fs = require("@lune/fs")
local Process = require("@lune/process")
local Serde = require("@lune/serde")
local Contract = require("@ci/bootstrap/contract")
local Executor = require("@ci/bootstrap/executor")
local Glob = require("@ci/bootstrap/glob")
local Reporter = require("@ci/bootstrap/reporter")
local Workflow = require("./workflow")

const ARTIFACT_ROOT = "build/github/artifacts"

local TaskRunner = {}

local function command(arguments: { string }, input: string?): string
	local result = Process.exec("tar", arguments, { stdio = { stdin = input } })
	if not result.ok then
		error("Unable to transfer component outputs with tar", 0)
	end
	return result.stdout
end

local function declared(path: string, outputs: { string }): boolean
	if path:sub(1, 1) == "/" or path:find("\\", 1, true) or path:find("[:%c]") then
		return false
	end
	for segment in path:gmatch("[^/]+") do
		if segment == "." or segment == ".." then
			return false
		end
	end
	for _, pattern in outputs do
		if Glob.Match(path, pattern) then
			return true
		end
	end
	return false
end

-- Reject links, special files, traversal, and writes outside declared outputs.
local function validateArchive(path: string, task: Contract.Task): ()
	for line in command({ "-tvf", path }):gmatch("[^\r\n]+") do
		local kind = line:sub(1, 1)
		if kind ~= "-" and kind ~= "d" then
			error(`{task.identity}: output archive contains a link or special file`, 0)
		end
	end
	for name in command({ "-tf", path }):gmatch("[^\r\n]+") do
		local normalized = name:gsub("/+$", "")
		if not declared(normalized, task.outputs) then
			error(`{task.identity}: archive entry is outside declared outputs`, 0)
		end
	end
end

local function bundle(task: Contract.Task): ()
	local paths: { string } = {}
	local seen: { [string]: boolean } = {}
	for _, pattern in task.outputs do
		for _, path in Glob.Find(pattern) do
			if seen[path] then
				continue
			end
			if not declared(path, task.outputs) then
				error(`{task.identity}: unsafe output path`, 0)
			end
			seen[path] = true
			table.insert(paths, path)
		end
	end
	table.sort(paths)
	Fs.writeDir(ARTIFACT_ROOT)
	local archive = `{ARTIFACT_ROOT}/{task.identity}.tar`
	command(
		{ "-cf", archive, "--no-recursion", "--null", "--files-from", "-" },
		table.concat(paths, "\0") .. (if #paths > 0 then "\0" else "")
	)
	validateArchive(archive, task)
end

function TaskRunner.Run(tasks: { Contract.Task }, event: string, identity: string): ()
	local indexed: { [string]: Contract.Task } = {}
	for _, task in tasks do
		indexed[task.identity] = task
	end
	local selected = indexed[identity]
	if not selected then
		error(`component {identity} is not in the validated execution plan`, 0)
	end
	for _, dependency in selected.needs do
		local provider = indexed[dependency]
		if not provider then
			error(`{identity}: dependency {dependency} is not in the plan`, 0)
		end
		if #provider.outputs == 0 then
			continue
		end
		local archive = `{ARTIFACT_ROOT}/{dependency}.tar`
		if not Fs.isFile(archive) then
			error(`{identity}: missing dependency artifact {dependency}`, 0)
		end
		validateArchive(archive, provider)
		command({ "--extract", "--file", archive, "--no-same-owner", "--no-same-permissions" })
	end
	local executor = Executor.new()
	print(`::notice::Starting {identity}`)
	if not executor:Invoke(selected, event) then
		error(`component {identity} failed`, 0)
	end
	local missing = executor:MissingOutputs(selected.outputs)
	if #missing > 0 then
		error(`{identity}: missing declared outputs {table.concat(missing, ", ")}`, 0)
	end
	if #selected.outputs > 0 then
		bundle(selected)
	end
	print(`::notice::Completed {identity}`)
end

function TaskRunner.Report(tasks: { Contract.Task }): ()
	local encoded = Process.env.CI_JOB_RESULTS
	if not encoded then
		error("CI_JOB_RESULTS is missing", 0)
	end
	local decoded: unknown = Serde.decode("json", encoded)
	if type(decoded) ~= "table" then
		error("CI_JOB_RESULTS must contain a job-result object", 0)
	end
	local results: { [string]: unknown } = {}
	for name, value in decoded do
		if type(name) == "string" then
			results[name] = value
		end
	end
	local outcomes: { [string]: string } = {}
	local passed = true
	for _, task in tasks do
		local value = results[Workflow.JobId(task.identity)]
		local result = if type(value) == "table" and type(value.result) == "string" then value.result else "skipped"
		outcomes[task.identity] = if result == "success"
			then "passed"
			else if result == "skipped" then "blocked" else result
		if result ~= "success" then
			passed = false
		end
	end
	Reporter.new():Report(outcomes, #tasks)
	if not passed then
		error("one or more discovered CI components failed or were blocked", 0)
	end
end

return TaskRunner
