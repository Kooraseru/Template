-- ci/github/workflows/taskRunner.luau
--!strict

local Fs = require("@std/fs")
local Json = require("@formats/json")
local Process = require("@lute/process")
local Contract = require("@ci/bootstrap/contracts/contract")
local Executor = require("@ci/bootstrap/execution/executor")
local Glob = require("@ci/bootstrap/discovery/glob")
local Reporter = require("@ci/bootstrap/outcomes/reporter")
local Workflow = require("@ci/github/workflows/workflow")
local Publication = require("@ci/github/publication")
local Configuration = require("@ci/github/configuration")
local Credentials = require("@ci/github/authentication/credentials")
local SkipPolicy = require("@ci/bootstrap/outcomes/skipPolicy")
local Responses = require("@ci/github/reporting/responses")

local Artifacts = require("@ci/github/workflows/artifacts")
const ARTIFACT_ROOT = Artifacts.Transport()

local TaskRunner = {}

local function command(arguments: { string }): string
	local result = Process.run({ "tar", table.unpack(arguments) })
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

local function bundle(task: Contract.Task, outcome: string?): ()
	local paths: { string } = {}
	local seen: { [string]: boolean } = {}

	for _, pattern in (if outcome == "skipped" then {} else task.outputs) do
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
	Fs.createDirectory(ARTIFACT_ROOT, { makeParents = true })
	local directory = `{ARTIFACT_ROOT}/{Contract.Key(task.identity)}`
	Fs.createDirectory(directory, { makeParents = true })
	local archive = `{directory}/outputs.tar`
	Fs.writeStringToFile(`{directory}/manifest.json`, Json.encode(Artifacts.Manifest(task, outcome)))
	local manifest = `{ARTIFACT_ROOT}/files-{Process.pid()}.txt`
	Fs.writeStringToFile(manifest, table.concat(paths, "\0") .. (if #paths > 0 then "\0" else ""))
	command({ "-cf", archive, "--no-recursion", "--null", "--files-from", manifest })
	Fs.remove(manifest)
	validateArchive(archive, task)
end

function TaskRunner.Verify(task: Contract.Task): string
	local directory = `{ARTIFACT_ROOT}/{Contract.Key(task.identity)}`
	local archive = `{directory}/outputs.tar`
	if not Fs.exists(archive) or Fs.type(archive) ~= "file" then
		error(`{task.identity}: missing output archive`, 0)
	end
	validateArchive(archive, task)
	command({ "--extract", "--file", archive, "--no-same-owner", "--no-same-permissions" })
	return Artifacts.Verify(`{directory}/manifest.json`, task)
end

function TaskRunner.Run(
	tasks: { Contract.Task },
	event: string,
	identity: string,
	credentials: Credentials.Credentials?
): ()
	Process.env.CI_COMPONENT = identity
	Responses.Prepare()
	local indexed: { [string]: Contract.Task } = {}
	for _, task in tasks do
		indexed[task.identity] = task
	end
	local selected = indexed[identity]
	if not selected then
		error(`component {identity} is not in the validated execution plan`, 0)
	end
	if Process.env.ACT == "true" and selected.phase == "publish" then error("Local publication is disabled", 0) end
	if selected.phase ~= (if Process.env.CI_PHASE == "publish" then "publish" else "build") then error("Component is outside the selected execution phase", 0) end
	local skipConclusion = SkipPolicy.Conclusion(identity)

	for _, dependency in selected.needs do
		local provider = indexed[dependency]
		if not provider then
			error(`{identity}: dependency {dependency} is not in the plan`, 0)
		end
				local directory = `{ARTIFACT_ROOT}/{Contract.Key(dependency)}`
		local archive = `{directory}/outputs.tar`
		if not Fs.exists(archive) or Fs.type(archive) ~= "file" then
			error(`{identity}: missing dependency artifact {dependency}`, 0)
		end
		if TaskRunner.Verify(provider) ~= "passed" then error(`{identity}: prerequisite {dependency} was skipped`, 0) end
	end

	local executor = Executor.new(credentials)
	print(`::notice::Starting {identity}`)
	local outcome = executor:Invoke(selected, event)
	if outcome ~= "passed" and credentials and Process.env.CI_GRAPH_RUN == "true" and Process.env.ACT ~= "true" then
		credentials:WarnUnavailable(Configuration.new(), "source-ci", identity, selected.credentials)
	end

	if outcome == "skipped" then
		bundle(selected, "skipped")
		Publication.Output("outcome", "skipped")
		Publication.Output("skipped", "true")
		print(`::notice::Skipped {identity}`)
		if skipConclusion == "failure" then
			error(`component outcome is skipped; configured native job conclusion is failure`, 0)
		end
		return
	end

	if outcome == "failed" then
		error(`component {identity} failed`, 0)
	end
	local missing = executor:MissingOutputs(selected.outputs)
	if #missing > 0 then
		error(`{identity}: missing declared outputs {table.concat(missing, ", ")}`, 0)
	end
	bundle(selected)
	Publication.Output("outcome", "passed")
	Publication.Output("skipped", "false")
	print(`::notice::Completed {identity}`)
end

function TaskRunner.Report(tasks: { Contract.Task }, credentials: Credentials.Credentials): ()
	local encoded = Process.env.CI_JOB_RESULTS
	if not encoded then
		error("CI_JOB_RESULTS is missing", 0)
	end
	local decoded: unknown = Json.decode(encoded)
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
	local responseTransferFailed = Process.env.CI_RESPONSE_DOWNLOAD_OUTCOME == "failure"
	local passed = not responseTransferFailed
	if responseTransferFailed then
		Responses.Record("execution/response-transfer", Responses.Template("execution.response-transfer"), "warning")
	end

	local expected: { [string]: boolean } = {}
	for _, task in tasks do expected[task.identity] = true end
	for _, task in tasks do
		local value = results[Workflow.JobId(task.identity)]
		local result = if type(value) == "table" and type(value.result) == "string" then value.result else "skipped"
		local job: { [string]: unknown } = if type(value) == "table" then Publication.Record(value) else {}
		local outputs = job.outputs
		local skipped = type(outputs) == "table" and Publication.Record(outputs).outcome == "skipped"
		outcomes[task.identity] = if skipped then "skipped"
			elseif result == "success" then "passed" elseif result == "skipped" then "blocked" else result
		if skipped and result == "success" and SkipPolicy.Conclusion(task.identity) == "neutral" and Process.env.CI_PHASE == "publish" then
			local reported, problem = pcall(SkipPolicy.ReportNeutral, task.identity, credentials)
			if not reported then
				print(`::error::{problem}`)
				outcomes[task.identity] = "skipped (neutral Check Run failed)"
				passed = false
			end
		end
		if outcomes[task.identity] == "blocked" then
			local blockers: { string } = {}
			for _, dependency in task.needs do
				local prerequisite = results[Workflow.JobId(dependency)]
				if expected[dependency] and (type(prerequisite) ~= "table" or prerequisite.result ~= "success") then
					table.insert(blockers, dependency)
				end
			end
			if #blockers > 0 then
				outcomes[task.identity] = "blocked (prerequisites: " .. table.concat(blockers, ", ") .. ")"
			end
		end
		if result ~= "success" or (skipped and SkipPolicy.Conclusion(task.identity) == "failure") then
			passed = false
		end
	end

	Reporter.new():Report(outcomes, #tasks, responseTransferFailed)
	if not passed then
		error("one or more discovered CI components failed or were blocked", 0)
	end
end

return TaskRunner
