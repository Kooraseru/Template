-- ci/github/workflows/artifacts.luau
--!strict

local Fs = require("@std/fs")
local Process = require("@lute/process")
local Json = require("@formats/json")
local Hash = require("@formats/hash")
local Glob = require("@ci/bootstrap/discovery/glob")
local Contract = require("@ci/bootstrap/contracts/contract")

local Artifacts = {}
export type File = { path: string, size: number, sha256: string }
export type Manifest = { version: number, runId: string, source: string, workspaceDigest: string, operation: string, phase: string, component: string, outcome: string, complete: boolean, files: { File } }

--- Select one safe identity for all output produced by this invocation.
function Artifacts.RunId(): string
	local id = Process.env.CI_LOCAL_RUN_ID or Process.env.CI_RUN_ID or `{Process.env.GITHUB_RUN_ID or "cli"}-{Process.env.GITHUB_RUN_ATTEMPT or tostring(Process.pid())}`
	if not id:match("^[%w_-]+$") then error("Unsafe execution run identity", 0) end
	return id
end

--- Resolve a stage directory independently of product output paths.
function Artifacts.Stage(phase: string?): string
	local selected = phase or Process.env.CI_PHASE or "start"
	if not table.find({ "start", "validation", "readiness", "build", "publish" }, selected) then error("Unknown execution stage", 0) end
	return `build/run/{Artifacts.RunId()}/{selected}`
end

--- Bundles are transport state, never compiled deliverables.
function Artifacts.Transport(): string
	return `build/run/{Artifacts.RunId()}/transport/bundles`
end

--- Limit output files to the producing component's declared namespace.
function Artifacts.Declared(file: string, task: Contract.Task): boolean
	if file:find("\\", 1, true) or file:find("[:%c]") or file:sub(1, 1) == "/" then return false end
	for part in file:gmatch("[^/]+") do
		if part == "." or part == ".." then return false end
	end
	if not (file:sub(1, 16) == "build/artifacts/" or file:sub(1, 13) == "build/github/") then return false end
	for _, pattern in task.outputs do
		if Glob.Match(file, pattern) then return true end
	end
	return false
end

--- Record file bytes and provenance only after the component completes successfully.
function Artifacts.Manifest(task: Contract.Task, outcome: string?): Manifest
	local files: { File } = {}
	local seen: { [string]: boolean } = {}
	for _, pattern in (if outcome == "skipped" then {} else task.outputs) do
		for _, file in Glob.Find(pattern) do
			if Fs.type(file) ~= "file" or seen[file] then continue end
			if not Artifacts.Declared(file, task) then error(`Unsafe output {file}`, 0) end
			local content = Fs.readFileToString(file)
			table.insert(files, { path = file, size = #content, sha256 = Hash.sha256(content) })
			seen[file] = true
		end
	end
	table.sort(files, function(a: File, b: File): boolean return a.path < b.path end)
	return { version = 1, runId = Artifacts.RunId(), source = Process.env.CI_SOURCE_SHA or Process.env.GITHUB_SHA or "unknown", workspaceDigest = Process.env.CI_WORKSPACE_DIGEST or Process.env.CI_SOURCE_SHA or Process.env.GITHUB_SHA or "unknown", operation = Process.env.CI_OPERATION or "validation", phase = task.phase, component = task.identity, outcome = outcome or "passed", complete = true, files = files }
end

--- Verify provenance and file bytes before a consumer executes; never rebuild a missing input.
function Artifacts.Verify(file: string, task: Contract.Task): string
	local manifest = Json.decode(Fs.readFileToString(file)) :: Manifest
	if manifest.version ~= 1 or not manifest.complete or (manifest.outcome ~= "passed" and manifest.outcome ~= "skipped") or manifest.component ~= task.identity
		or manifest.runId ~= Artifacts.RunId() or manifest.source ~= (Process.env.CI_SOURCE_SHA or Process.env.GITHUB_SHA or "unknown")
		or manifest.workspaceDigest ~= (Process.env.CI_WORKSPACE_DIGEST or Process.env.CI_SOURCE_SHA or Process.env.GITHUB_SHA or "unknown")
		or manifest.operation ~= (Process.env.CI_OPERATION or "validation") or manifest.phase ~= task.phase or type(manifest.files) ~= "table" then
		error(`{task.identity}: output provenance mismatch`, 0)
	end
	for _, item in manifest.files do
		if type(item.path) ~= "string" or not Artifacts.Declared(item.path, task) or Fs.type(item.path) ~= "file" then error("Invalid output manifest path", 0) end
		local content = Fs.readFileToString(item.path)
		if #content ~= item.size or Hash.sha256(content) ~= item.sha256 then error(`{task.identity}: output hash mismatch`, 0) end
	end
	return manifest.outcome
end

return Artifacts
